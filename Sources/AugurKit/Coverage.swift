@preconcurrency import Foundation

// MARK: - Coverage Query

/// The result of querying a `CoverageReport` for a file's changed lines.
///
/// Counts are restricted to the *instrumented* changed lines: a changed line
/// the coverage tool never instrumented (e.g. a comment or a blank line)
/// contributes to neither `covered` nor `instrumented`.
public struct CoverageQuery: Sendable, Equatable {
    /// Number of instrumented changed lines that are covered (hits > 0).
    public let covered: Int
    /// Number of changed lines that the report instrumented at all.
    public let instrumented: Int
    /// Whether the file path matched any file in the report.
    public let fileMatched: Bool

    public init(covered: Int, instrumented: Int, fileMatched: Bool) {
        self.covered = covered
        self.instrumented = instrumented
        self.fileMatched = fileMatched
    }

    /// Fraction of instrumented changed lines that are covered (0...1), or `nil`
    /// when no changed line was instrumented (so a ratio is undefined).
    public var coveredFraction: Double? {
        guard instrumented > 0 else { return nil }
        return Double(covered) / Double(instrumented)
    }
}

// MARK: - Coverage Report

/// A parsed line-coverage report (LCOV or Cobertura), queryable per file.
///
/// Stores, per source file, the instrumented line numbers and which of those
/// are covered (hits > 0). Path matching between diff paths and coverage paths
/// is by normalized longest-suffix (see `query(path:changedLines:)`), because
/// the two often disagree on a leading prefix (`src/a.swift` vs
/// `/build/src/a.swift`).
public struct CoverageReport: Sendable, Equatable {
    /// Per-file coverage: instrumented line numbers and the covered subset.
    public struct FileCoverage: Sendable, Equatable {
        /// The source file path as reported by the coverage tool.
        public let path: String
        /// All line numbers the tool instrumented.
        public let instrumented: Set<Int>
        /// The instrumented lines with hits > 0.
        public let covered: Set<Int>

        public init(path: String, instrumented: Set<Int>, covered: Set<Int>) {
            self.path = path
            self.instrumented = instrumented
            self.covered = covered
        }
    }

    /// All files in the report, keyed by their reported path.
    public let files: [String: FileCoverage]

    public init(files: [FileCoverage]) {
        var byPath: [String: FileCoverage] = [:]
        for file in files {
            if let existing = byPath[file.path] {
                // Merge duplicate records (e.g. a file split across LCOV records).
                byPath[file.path] = FileCoverage(
                    path: file.path,
                    instrumented: existing.instrumented.union(file.instrumented),
                    covered: existing.covered.union(file.covered)
                )
            } else {
                byPath[file.path] = file
            }
        }
        self.files = byPath
    }

    // MARK: - Query

    /// Coverage of a diff file's changed lines.
    ///
    /// The file is matched by normalized longest-suffix against the report's
    /// paths (see `matchFile(diffPath:)`). When matched, only changed lines that
    /// the report instrumented count toward `instrumented`; the covered subset of
    /// those counts toward `covered`.
    /// - Parameters:
    ///   - path: The diff file path.
    ///   - changedLines: The added line numbers for that file.
    /// - Returns: A `CoverageQuery` describing the match.
    public func query(path: String, changedLines: [Int]) -> CoverageQuery {
        guard let file = matchFile(diffPath: path) else {
            return CoverageQuery(covered: 0, instrumented: 0, fileMatched: false)
        }
        let changed = Set(changedLines)
        let instrumentedChanged = changed.intersection(file.instrumented)
        let coveredChanged = instrumentedChanged.intersection(file.covered)
        return CoverageQuery(
            covered: coveredChanged.count,
            instrumented: instrumentedChanged.count,
            fileMatched: true
        )
    }

    /// Finds the report file whose path best matches a diff path.
    ///
    /// Matching is by normalized longest common suffix at path-component
    /// boundaries: the report file sharing the most trailing components with the
    /// diff path wins. Limitation: when two report files share an identical
    /// suffix (e.g. `a/util.swift` and `b/util.swift` against a diff path
    /// `util.swift`), the match is ambiguous and resolved deterministically by
    /// shorter reported path then lexicographic order — it may not be the file
    /// you intended. Prefer emitting coverage with repo-relative paths.
    /// - Parameter diffPath: The diff file path to match.
    /// - Returns: The best-matching `FileCoverage`, or `nil` if none share a
    ///   trailing path component.
    public func matchFile(diffPath: String) -> FileCoverage? {
        if let exact = files[diffPath] { return exact }
        let normalizedDiff = Self.normalize(diffPath)
        if let exact = files.values.first(where: { Self.normalize($0.path) == normalizedDiff }) {
            return exact
        }

        let diffComponents = Self.components(normalizedDiff)
        var best: FileCoverage?
        var bestScore = 0
        for candidate in files.values {
            let score = Self.suffixMatchLength(
                Self.components(Self.normalize(candidate.path)),
                diffComponents
            )
            guard score > 0 else { continue }
            if score > bestScore {
                bestScore = score
                best = candidate
            } else if score == bestScore, let current = best {
                // Deterministic tie-break: shorter path, then lexicographic.
                if candidate.path.count < current.path.count
                    || (candidate.path.count == current.path.count && candidate.path < current.path) {
                    best = candidate
                }
            }
        }
        return best
    }

    // MARK: - Path Normalization

    /// Normalizes a path for matching: backslashes to slashes, strips a leading
    /// `./`, and collapses repeated slashes.
    static func normalize(_ path: String) -> String {
        var result = path.replacingOccurrences(of: "\\", with: "/")
        while result.hasPrefix("./") { result.removeFirst(2) }
        while result.contains("//") { result = result.replacingOccurrences(of: "//", with: "/") }
        return result
    }

    /// Splits a normalized path into non-empty components.
    static func components(_ normalized: String) -> [Substring] {
        normalized.split(separator: "/", omittingEmptySubsequences: true)
    }

    /// The number of trailing components two paths share.
    static func suffixMatchLength(_ lhs: [Substring], _ rhs: [Substring]) -> Int {
        var count = 0
        var leftIndex = lhs.count - 1
        var rightIndex = rhs.count - 1
        while leftIndex >= 0, rightIndex >= 0, lhs[leftIndex] == rhs[rightIndex] {
            count += 1
            leftIndex -= 1
            rightIndex -= 1
        }
        return count
    }
}

// MARK: - Parsing

/// Parses LCOV, Cobertura, JaCoCo, and Go coverprofile reports into a
/// `CoverageReport`.
///
/// Foundation-only (LCOV and Go coverprofile by line parsing, Cobertura and
/// JaCoCo via `XMLParser`), so `AugurKit` stays dependency-free.
public enum CoverageParser {
    /// The coverage report format.
    public enum Format: Sendable, Equatable {
        case lcov
        case cobertura
        case jacoco
        case go
    }

    /// Parsing failures surfaced to callers.
    public enum ParseError: Error, LocalizedError, Sendable {
        case undetectableFormat
        case malformedXML(String)

        public var errorDescription: String? {
            switch self {
            case .undetectableFormat:
                return "Could not detect coverage format (expected LCOV, Cobertura/JaCoCo XML, or Go coverprofile)."
            case .malformedXML(let detail):
                return "Malformed coverage XML: \(detail)"
            }
        }
    }

    /// Detects the format from a file path and/or its contents.
    ///
    /// Extension hints first: `.info` → LCOV, `.out` → Go coverprofile, `.xml` →
    /// Cobertura *unless* the body looks like JaCoCo. Otherwise content sniffing:
    /// a first non-empty line beginning `mode:` → Go; XML mentioning `jacoco` or
    /// containing `<report`/`<sourcefile` → JaCoCo; a leading `<?xml` or a
    /// `<coverage` tag → Cobertura; an `SF:`/`DA:` marker → LCOV.
    /// - Parameters:
    ///   - path: The file path (may be empty when only content is known).
    ///   - contents: The file contents.
    /// - Returns: The detected format, or `nil` if undetectable.
    public static func detectFormat(path: String, contents: String) -> Format? {
        let lowerPath = path.lowercased()
        if lowerPath.hasSuffix(".info") { return .lcov }
        if lowerPath.hasSuffix(".out") { return .go }

        // Go coverprofiles begin with a `mode:` line.
        if isGoProfile(contents) { return .go }

        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        let looksXML = trimmed.hasPrefix("<?xml") || trimmed.hasPrefix("<")
        if looksXML || lowerPath.hasSuffix(".xml") {
            // JaCoCo and Cobertura are both XML; disambiguate by their markers.
            if isJaCoCo(contents) { return .jacoco }
            if lowerPath.hasSuffix(".xml") || trimmed.contains("<coverage") { return .cobertura }
        }
        if trimmed.hasPrefix("<?xml") || trimmed.contains("<coverage") { return .cobertura }
        if contents.contains("\nSF:") || contents.hasPrefix("SF:")
            || contents.contains("\nDA:") || contents.hasPrefix("DA:") { return .lcov }
        return nil
    }

    /// Whether the contents' first non-empty line starts with `mode:` (Go).
    private static func isGoProfile(_ contents: String) -> Bool {
        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            return line.hasPrefix("mode:")
        }
        return false
    }

    /// Whether the XML contents carry a JaCoCo signature (DOCTYPE/marker or the
    /// `<report>`+`<sourcefile>` element pairing).
    private static func isJaCoCo(_ contents: String) -> Bool {
        if contents.contains("jacoco") || contents.contains("JACOCO") { return true }
        return contents.contains("<report") && contents.contains("<sourcefile")
    }

    /// Loads and parses a coverage file from disk, auto-detecting the format.
    /// - Parameter path: The path to a coverage report (LCOV `.info`, Cobertura
    ///   or JaCoCo `.xml`, or a Go `.out` coverprofile).
    /// - Returns: The parsed `CoverageReport`.
    /// - Throws: `ParseError` on detection/parse failure, or an I/O error if the
    ///   file cannot be read.
    public static func load(path: String) throws -> CoverageReport {
        guard let data = FileManager.default.contents(atPath: path) else {
            throw ParseError.undetectableFormat
        }
        let contents = String(decoding: data, as: UTF8.self)
        return try parse(contents: contents, path: path)
    }

    /// Parses coverage contents, auto-detecting the format.
    /// - Parameters:
    ///   - contents: The report text.
    ///   - path: The originating path, used for format detection.
    /// - Returns: The parsed `CoverageReport`.
    public static func parse(contents: String, path: String = "") throws -> CoverageReport {
        guard let format = detectFormat(path: path, contents: contents) else {
            throw ParseError.undetectableFormat
        }
        switch format {
        case .lcov: return parseLCOV(contents)
        case .cobertura: return try parseCobertura(contents)
        case .jacoco: return try parseJaCoCo(contents)
        case .go: return parseGoProfile(contents)
        }
    }

    // MARK: - LCOV

    /// Parses an LCOV report.
    ///
    /// Records end at `end_of_record`. `SF:<path>` opens a file; `DA:<line>,<hits>`
    /// records an instrumented line and its hit count (covered when hits > 0).
    /// - Parameter contents: The LCOV text.
    /// - Returns: The parsed report.
    public static func parseLCOV(_ contents: String) -> CoverageReport {
        var files: [CoverageReport.FileCoverage] = []
        var currentPath: String?
        var instrumented: Set<Int> = []
        var covered: Set<Int> = []

        func flush() {
            if let path = currentPath {
                files.append(CoverageReport.FileCoverage(path: path, instrumented: instrumented, covered: covered))
            }
            currentPath = nil
            instrumented = []
            covered = []
        }

        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line == "end_of_record" {
                flush()
            } else if line.hasPrefix("SF:") {
                if currentPath != nil { flush() }
                currentPath = String(line.dropFirst(3))
            } else if line.hasPrefix("DA:") {
                let payload = line.dropFirst(3)
                let parts = payload.split(separator: ",", maxSplits: 2, omittingEmptySubsequences: false)
                guard parts.count >= 2, let number = Int(parts[0]) else { continue }
                let hits = Int(parts[1]) ?? 0
                instrumented.insert(number)
                if hits > 0 { covered.insert(number) }
            }
        }
        flush()
        return CoverageReport(files: files)
    }

    // MARK: - Cobertura

    /// Parses a Cobertura XML report.
    ///
    /// Reads `<class filename="...">` elements and their nested
    /// `<lines><line number="N" hits="H"/></lines>`, handling
    /// `packages/package/classes/class` nesting.
    /// - Parameter contents: The Cobertura XML text.
    /// - Returns: The parsed report.
    /// - Throws: `ParseError.malformedXML` if the document cannot be parsed.
    public static func parseCobertura(_ contents: String) throws -> CoverageReport {
        let data = Data(contents.utf8)
        let parser = XMLParser(data: data)
        let delegate = CoberturaDelegate()
        parser.delegate = delegate
        guard parser.parse() else {
            let reason = parser.parserError.map { String(describing: $0) } ?? "unknown error"
            throw ParseError.malformedXML(reason)
        }
        return CoverageReport(files: delegate.fileCoverages())
    }

    // MARK: - JaCoCo

    /// Parses a JaCoCo XML report (Kotlin/Java).
    ///
    /// Reads `<package name="...">` elements and their nested
    /// `<sourcefile name="...">` with `<line nr="N" mi="M" ci="C"/>` rows. A line
    /// is instrumented when it has a `line` element and covered when `ci`
    /// (covered instructions) > 0. The reported file path is `package@name` + `/`
    /// + `sourcefile@name` (e.g. `com/foo` + `Bar.kt` → `com/foo/Bar.kt`),
    /// reconciled with diff paths by the existing suffix matching.
    /// - Parameter contents: The JaCoCo XML text.
    /// - Returns: The parsed report.
    /// - Throws: `ParseError.malformedXML` if the document cannot be parsed.
    public static func parseJaCoCo(_ contents: String) throws -> CoverageReport {
        let data = Data(contents.utf8)
        let parser = XMLParser(data: data)
        // JaCoCo documents carry a DOCTYPE/DTD reference; never resolve it.
        parser.shouldResolveExternalEntities = false
        let delegate = JaCoCoDelegate()
        parser.delegate = delegate
        guard parser.parse() else {
            let reason = parser.parserError.map { String(describing: $0) } ?? "unknown error"
            throw ParseError.malformedXML(reason)
        }
        return CoverageReport(files: delegate.fileCoverages())
    }

    // MARK: - Go coverprofile

    /// Parses a Go coverprofile (`go test -coverprofile=cover.out`).
    ///
    /// The first non-empty line is `mode: set|count|atomic`; each subsequent line
    /// is `path/file.go:startLine.startCol,endLine.endCol numStmts count`. Every
    /// line in `startLine...endLine` is instrumented; the block is covered when
    /// `count` > 0. Blocks accumulate per file, so a line is covered when *any*
    /// block over it has `count` > 0.
    /// The largest line span a single Go coverprofile block may declare before it
    /// is rejected as implausible. No real source file approaches a million lines,
    /// so this bounds allocation against a crafted profile without affecting any
    /// legitimate coverage data.
    static let maxGoBlockSpan = 1_000_000

    /// - Parameter contents: The coverprofile text.
    /// - Returns: The parsed report.
    public static func parseGoProfile(_ contents: String) -> CoverageReport {
        var perFile: [String: (instrumented: Set<Int>, covered: Set<Int>)] = [:]

        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("mode:") { continue }
            guard let block = parseGoBlock(line) else { continue }
            // Guard against a malicious or corrupt profile whose block spans an
            // absurd line range (e.g. `f.go:1.0,2000000000.0 3 1`): materializing
            // every line into the set would allocate multiple gigabytes and hang.
            // Real coverprofiles never span anywhere near this, so skipping such a
            // block cannot affect a legitimate file's coverage.
            guard block.endLine - block.startLine < maxGoBlockSpan else { continue }
            var entry = perFile[block.path] ?? (instrumented: [], covered: [])
            for number in block.startLine...block.endLine {
                entry.instrumented.insert(number)
                if block.count > 0 { entry.covered.insert(number) }
            }
            perFile[block.path] = entry
        }

        let files = perFile.map { path, value in
            CoverageReport.FileCoverage(path: path, instrumented: value.instrumented, covered: value.covered)
        }
        return CoverageReport(files: files)
    }

    /// Parses one Go coverprofile block line:
    /// `path/file.go:startLine.startCol,endLine.endCol numStmts count`.
    /// The file path may itself contain colons on some platforms, so the
    /// position span is split from the *last* colon.
    /// - Parameter line: The trimmed block line.
    /// - Returns: The parsed block, or `nil` if it is malformed.
    static func parseGoBlock(_ line: String) -> (path: String, startLine: Int, endLine: Int, count: Int)? {
        guard let colonIndex = line.lastIndex(of: ":") else { return nil }
        let path = String(line[line.startIndex..<colonIndex])
        let rest = line[line.index(after: colonIndex)...]
        guard !path.isEmpty else { return nil }

        // rest = "startLine.startCol,endLine.endCol numStmts count"
        let fields = rest.split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count >= 3, let count = Int(fields[fields.count - 1]) else { return nil }
        let span = fields[0]
        let endpoints = span.split(separator: ",", omittingEmptySubsequences: false)
        guard endpoints.count == 2 else { return nil }
        guard
            let startLine = Int(endpoints[0].split(separator: ".").first ?? ""),
            let endLine = Int(endpoints[1].split(separator: ".").first ?? ""),
            startLine >= 1,
            endLine >= startLine
        else { return nil }
        return (path: path, startLine: startLine, endLine: endLine, count: count)
    }
}

// MARK: - Cobertura XML Delegate

/// Accumulates per-class line coverage while parsing a Cobertura document.
private final class CoberturaDelegate: NSObject, XMLParserDelegate {
    private var perFile: [String: (instrumented: Set<Int>, covered: Set<Int>)] = [:]
    private var currentFilename: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        switch elementName {
        case "class":
            currentFilename = attributeDict["filename"]
            if let filename = currentFilename, perFile[filename] == nil {
                perFile[filename] = (instrumented: [], covered: [])
            }
        case "line":
            guard
                let filename = currentFilename,
                let numberText = attributeDict["number"],
                let number = Int(numberText)
            else { return }
            let hits = Int(attributeDict["hits"] ?? "0") ?? 0
            perFile[filename, default: (instrumented: [], covered: [])].instrumented.insert(number)
            if hits > 0 {
                perFile[filename, default: (instrumented: [], covered: [])].covered.insert(number)
            }
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "class" {
            currentFilename = nil
        }
    }

    func fileCoverages() -> [CoverageReport.FileCoverage] {
        perFile.map { path, value in
            CoverageReport.FileCoverage(path: path, instrumented: value.instrumented, covered: value.covered)
        }
    }
}

// MARK: - JaCoCo XML Delegate

/// Accumulates per-sourcefile line coverage while parsing a JaCoCo document.
///
/// The active `<package name>` is prepended to each `<sourcefile name>` to form
/// the reported path. A `<line>` row is instrumented; covered when `ci` > 0.
private final class JaCoCoDelegate: NSObject, XMLParserDelegate {
    private var perFile: [String: (instrumented: Set<Int>, covered: Set<Int>)] = [:]
    private var currentPackage: String?
    private var currentPath: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        switch elementName {
        case "package":
            currentPackage = attributeDict["name"]
        case "sourcefile":
            guard let name = attributeDict["name"] else { return }
            let path = Self.joinPath(package: currentPackage, sourcefile: name)
            currentPath = path
            if perFile[path] == nil {
                perFile[path] = (instrumented: [], covered: [])
            }
        case "line":
            guard
                let path = currentPath,
                let numberText = attributeDict["nr"],
                let number = Int(numberText)
            else { return }
            let coveredInstructions = Int(attributeDict["ci"] ?? "0") ?? 0
            perFile[path, default: (instrumented: [], covered: [])].instrumented.insert(number)
            if coveredInstructions > 0 {
                perFile[path, default: (instrumented: [], covered: [])].covered.insert(number)
            }
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "sourcefile":
            currentPath = nil
        case "package":
            currentPackage = nil
        default:
            break
        }
    }

    /// Joins a JaCoCo `package@name` and `sourcefile@name` into a path, tolerating
    /// a missing/empty package and any trailing slash on the package name.
    static func joinPath(package: String?, sourcefile: String) -> String {
        guard var pkg = package, !pkg.isEmpty else { return sourcefile }
        while pkg.hasSuffix("/") { pkg.removeLast() }
        guard !pkg.isEmpty else { return sourcefile }
        return "\(pkg)/\(sourcefile)"
    }

    func fileCoverages() -> [CoverageReport.FileCoverage] {
        perFile.map { path, value in
            CoverageReport.FileCoverage(path: path, instrumented: value.instrumented, covered: value.covered)
        }
    }
}
