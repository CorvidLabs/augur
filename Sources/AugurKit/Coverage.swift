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

/// Parses LCOV and Cobertura coverage reports into a `CoverageReport`.
///
/// Foundation-only (LCOV by line parsing, Cobertura via `XMLParser`), so
/// `AugurKit` stays dependency-free.
public enum CoverageParser {
    /// The coverage report format.
    public enum Format: Sendable, Equatable {
        case lcov
        case cobertura
    }

    /// Parsing failures surfaced to callers.
    public enum ParseError: Error, LocalizedError, Sendable {
        case undetectableFormat
        case malformedXML(String)

        public var errorDescription: String? {
            switch self {
            case .undetectableFormat:
                return "Could not detect coverage format (expected LCOV or Cobertura XML)."
            case .malformedXML(let detail):
                return "Malformed Cobertura XML: \(detail)"
            }
        }
    }

    /// Detects the format from a file path and/or its contents.
    ///
    /// `.info` → LCOV, `.xml` → Cobertura; otherwise content sniffing: a leading
    /// `<?xml` or a `<coverage` tag → Cobertura, an `SF:`/`DA:` marker → LCOV.
    /// - Parameters:
    ///   - path: The file path (may be empty when only content is known).
    ///   - contents: The file contents.
    /// - Returns: The detected format, or `nil` if undetectable.
    public static func detectFormat(path: String, contents: String) -> Format? {
        let lowerPath = path.lowercased()
        if lowerPath.hasSuffix(".info") { return .lcov }
        if lowerPath.hasSuffix(".xml") { return .cobertura }

        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("<?xml") || trimmed.contains("<coverage") { return .cobertura }
        if contents.contains("\nSF:") || contents.hasPrefix("SF:")
            || contents.contains("\nDA:") || contents.hasPrefix("DA:") { return .lcov }
        return nil
    }

    /// Loads and parses a coverage file from disk, auto-detecting the format.
    /// - Parameter path: The path to an LCOV (`.info`) or Cobertura (`.xml`) report.
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
