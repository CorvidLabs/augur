@preconcurrency import Foundation

// MARK: - Probe Protocol

/// Read-only access to the facts `augur` needs from a repository.
///
/// Abstracted so the engine can be tested against an in-memory fixture without
/// shelling out to git.
public protocol RepositoryProbe: Sendable {
    /// Files touched in the given scope.
    ///
    /// Implementations should populate `ChangedFile.addedLines` when they can, so
    /// per-line coverage scoring is available; the default protocol path leaves it
    /// empty (heuristic test-gap).
    func changedFiles(in scope: DiffScope) throws -> [ChangedFile]

    /// Recent commits (newest first), the basis for all history-derived signals.
    func recentCommits(limit: Int) throws -> [Commit]

    /// The current `HEAD` commit SHA, used to pin and detect stale calibration caches.
    func headSHA() throws -> String

    /// The added (new-revision) line numbers per file path in the scope.
    ///
    /// Used to refine the test-gap signal against a coverage report. The default
    /// returns `[:]`, so in-memory fixtures need not implement it.
    func addedLines(in scope: DiffScope) throws -> [String: [Int]]
}

extension RepositoryProbe {
    /// Default: probes without a real repository (e.g. test fixtures) report an
    /// empty SHA, which callers treat as "unknown HEAD".
    public func headSHA() throws -> String { "" }

    /// Default: no per-line information available.
    public func addedLines(in scope: DiffScope) throws -> [String: [Int]] { [:] }
}

// MARK: - Git Implementation

/// A `RepositoryProbe` backed by the `git` CLI.
public struct GitRepository: RepositoryProbe {
    private let path: String

    public init(path: String = ".") {
        self.path = path
    }

    /// Confirms `path` is inside a git work tree, throwing otherwise.
    public func validate() throws {
        let output = try run(["rev-parse", "--is-inside-work-tree"], allowFailure: true)
        guard output.trimmingCharacters(in: .whitespacesAndNewlines) == "true" else {
            throw AugurError.notARepository(path)
        }
    }

    public func changedFiles(in scope: DiffScope) throws -> [ChangedFile] {
        let numstat = try run(["diff", "--numstat"] + Self.scopeArgs(scope))
        let files = Self.parseNumstat(numstat)
        // Best-effort: enrich with added line ranges for per-line coverage.
        let added = (try? addedLines(in: scope)) ?? [:]
        guard !added.isEmpty else { return files }
        return files.map { file in
            ChangedFile(
                path: file.path,
                linesAdded: file.linesAdded,
                linesDeleted: file.linesDeleted,
                isBinary: file.isBinary,
                addedLines: added[file.path] ?? []
            )
        }
    }

    public func addedLines(in scope: DiffScope) throws -> [String: [Int]] {
        let output = try run(["diff", "--unified=0", "--no-color"] + Self.scopeArgs(scope), allowFailure: true)
        return Self.parseUnifiedZeroAddedLines(output)
    }

    /// Maps a `DiffScope` to its `git diff` argument(s).
    static func scopeArgs(_ scope: DiffScope) -> [String] {
        switch scope {
        case .range(let range): return [range]
        case .staged: return ["--cached"]
        case .workingTree: return ["HEAD"]
        }
    }

    public func recentCommits(limit: Int) throws -> [Commit] {
        // One log call powers churn, recency, ownership, coupling, and incidents.
        // Field separator: US (0x1f); record separator: a leading "\u{1e}".
        let format = "\u{1e}%H\u{1f}%ae\u{1f}%ct\u{1f}%s"
        let args = ["log", "-n", String(limit), "--no-merges", "--pretty=format:\(format)", "--name-only"]
        let output = try run(args, allowFailure: true)
        return Self.parseLog(output)
    }

    public func headSHA() throws -> String {
        let output = try run(["rev-parse", "HEAD"], allowFailure: true)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Parsing

    static func parseNumstat(_ output: String) -> [ChangedFile] {
        var files: [ChangedFile] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { continue }
            let addedField = String(parts[0])
            let deletedField = String(parts[1])
            let path = String(parts[2])
            let isBinary = addedField == "-" || deletedField == "-"
            files.append(
                ChangedFile(
                    path: path,
                    linesAdded: Int(addedField) ?? 0,
                    linesDeleted: Int(deletedField) ?? 0,
                    isBinary: isBinary
                )
            )
        }
        return files
    }

    /// Parses `git diff --unified=0` into the added (new-revision) line numbers
    /// per file.
    ///
    /// Tracks the current file via `+++ b/<path>` headers and reads hunk headers
    /// `@@ -a,b +c,d @@`: added lines span `c ..< c + d` (with `d` defaulting to
    /// `1` when omitted, and contributing none when `d == 0`).
    static func parseUnifiedZeroAddedLines(_ output: String) -> [String: [Int]] {
        var result: [String: [Int]] = [:]
        var currentPath: String?
        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix("+++ ") {
                currentPath = normalizeDiffHeaderPath(String(line.dropFirst(4)))
            } else if line.hasPrefix("@@") {
                guard let path = currentPath, let (start, count) = parseHunkAddedRange(line) else { continue }
                guard count > 0 else { continue }
                result[path, default: []].append(contentsOf: start..<(start + count))
            }
        }
        return result
    }

    /// Extracts the new-side `(start, count)` from a hunk header `@@ -a,b +c,d @@`.
    static func parseHunkAddedRange(_ header: String) -> (start: Int, count: Int)? {
        // Find the "+c,d" token between the first "+" after "@@" and the next space.
        guard let plusIndex = header.firstIndex(of: "+") else { return nil }
        let afterPlus = header[header.index(after: plusIndex)...]
        let token = afterPlus.prefix { $0 != " " && $0 != "@" }
        let parts = token.split(separator: ",", omittingEmptySubsequences: false)
        guard let start = Int(parts[0]) else { return nil }
        let count = parts.count > 1 ? (Int(parts[1]) ?? 1) : 1
        return (start, count)
    }

    /// Strips the `b/` (or `a/`) prefix git puts on diff header paths; returns
    /// `nil`-safe `/dev/null` as an empty path the caller ignores.
    static func normalizeDiffHeaderPath(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed == "/dev/null" { return nil }
        if trimmed.hasPrefix("b/") || trimmed.hasPrefix("a/") { return String(trimmed.dropFirst(2)) }
        return trimmed
    }

    static func parseLog(_ output: String) -> [Commit] {
        var commits: [Commit] = []
        for record in output.split(separator: "\u{1e}", omittingEmptySubsequences: true) {
            let lines = record.split(separator: "\n", omittingEmptySubsequences: false)
            guard let header = lines.first else { continue }
            let fields = header.split(separator: "\u{1f}", omittingEmptySubsequences: false)
            guard fields.count == 4 else { continue }
            let files = lines.dropFirst()
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            commits.append(
                Commit(
                    hash: String(fields[0]),
                    authorEmail: String(fields[1]),
                    timestamp: Int(fields[2]) ?? 0,
                    subject: String(fields[3]),
                    files: files
                )
            )
        }
        return commits
    }

    // MARK: - Process

    @discardableResult
    private func run(_ arguments: [String], allowFailure: Bool = false) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", path] + arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice  // avoid pipe-buffer deadlock
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard allowFailure || process.terminationStatus == 0 else {
            throw AugurError.git(command: arguments.joined(separator: " "), status: process.terminationStatus)
        }
        return String(decoding: data, as: UTF8.self)
    }
}
