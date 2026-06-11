@preconcurrency import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

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
        // `-z` yields NUL-delimited records and disables path quoting; it also
        // splits renames into `added\tdeleted\t<NUL>oldpath<NUL>newpath` so we can
        // resolve the synthetic `old => new` brace path to the real new path.
        let numstat = try run(["diff", "--numstat", "-z"] + Self.scopeArgs(scope))
        var files = Self.parseNumstat(numstat)
        // A working-tree assessment must see brand-new (never-`git add`ed) files:
        // `git diff HEAD` is silent about them, which would let a risk gate score
        // a fully untracked change as zero risk. Tracked paths win on collision.
        if scope == .workingTree {
            let tracked = Set(files.map(\.path))
            files += try untrackedFiles().filter { !tracked.contains($0.path) }
        }
        // Best-effort: enrich with added line ranges for per-line coverage.
        let added = (try? addedLines(in: scope)) ?? [:]
        guard !added.isEmpty else { return files }
        return files.map { file in
            ChangedFile(
                path: file.path,
                linesAdded: file.linesAdded,
                linesDeleted: file.linesDeleted,
                isBinary: file.isBinary,
                addedLines: added[file.path] ?? file.addedLines
            )
        }
    }

    public func addedLines(in scope: DiffScope) throws -> [String: [Int]] {
        let output = try run(["diff", "--unified=0", "--no-color"] + Self.scopeArgs(scope), allowFailure: true)
        var result = Self.parseUnifiedZeroAddedLines(output)
        // Untracked files never appear in `git diff`; every line of a new file is
        // an added line, so coverage and SARIF regions still line up.
        if scope == .workingTree {
            for file in (try? untrackedFiles()) ?? [] where !file.addedLines.isEmpty {
                result[file.path] = file.addedLines
            }
        }
        return result
    }

    /// Files present in the work tree but unknown to git, via
    /// `git ls-files --others --exclude-standard -z` (which honors `.gitignore`).
    ///
    /// Each is reported as a fully-added file: `linesAdded` is its on-disk line
    /// count, `linesDeleted` is `0`, and `addedLines` spans every line, so an
    /// untracked file is assessed exactly like a newly added one.
    internal func untrackedFiles() throws -> [ChangedFile] {
        let output = try run(["ls-files", "--others", "--exclude-standard", "-z"], allowFailure: true)
        let paths = output.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
        return paths.map { relativePath in
            let fullPath = (path as NSString).appendingPathComponent(relativePath)
            let data = FileManager.default.contents(atPath: fullPath) ?? Data()
            let isBinary = Self.looksBinary(data)
            let lineCount = isBinary ? 0 : Self.lineCount(of: data)
            return ChangedFile(
                path: relativePath,
                linesAdded: lineCount,
                linesDeleted: 0,
                isBinary: isBinary,
                addedLines: lineCount > 0 ? Array(1...lineCount) : []
            )
        }
    }

    /// Mirrors git's own binary heuristic: a NUL byte in the first 8000 bytes.
    static func looksBinary(_ data: Data) -> Bool {
        data.prefix(8000).contains(0)
    }

    /// Number of lines in a text blob: newline count, plus one for a final
    /// unterminated line. An empty blob has zero lines.
    static func lineCount(of data: Data) -> Int {
        guard !data.isEmpty else { return 0 }
        var count = 0
        for byte in data where byte == 0x0A { count += 1 }
        if data.last != 0x0A { count += 1 }
        return count
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
        // One log call powers churn, ownership, coupling, and incidents.
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

    /// Parses the NUL-delimited output of `git diff --numstat -z`.
    ///
    /// Tokens are split on NUL (`\0`). A normal record is one token of the form
    /// `added\tdeleted\t<path>`. A rename/copy record has an empty trailing path
    /// in its first token (`added\tdeleted\t`) and is followed by two further
    /// tokens: the old path then the new path. The new path is always used, so a
    /// rename resolves to its real destination rather than the synthetic
    /// `{old => new}` brace string git prints in non-`-z` mode. `-` line counts
    /// mark binary files.
    static func parseNumstat(_ output: String) -> [ChangedFile] {
        var files: [ChangedFile] = []
        let tokens = output.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            index += 1
            // A record token has two tabs: `added\tdeleted\t<path-or-empty>`.
            let parts = token.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { continue }
            let addedField = String(parts[0])
            let deletedField = String(parts[1])
            var path = String(parts[2])
            // Rename/copy: the path is empty here; old and new paths follow as
            // two separate NUL-delimited tokens. Resolve to the new path.
            if path.isEmpty {
                guard index + 1 < tokens.count else { continue }
                // tokens[index] is the old path; tokens[index + 1] is the new path.
                path = tokens[index + 1]
                index += 2
            }
            guard !path.isEmpty else { continue }
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
        // `core.quotepath=false` makes git emit verbatim UTF-8 paths instead of
        // octal-escaping non-ASCII bytes (e.g. `caf\303\251.go`), so CODEOWNERS,
        // exclude, and coverage matching see the real path. (`--numstat -z` also
        // disables quoting on its own; this covers every other git call.)
        let argv = ["git", "-C", path, "-c", "core.quotepath=false"] + arguments
        let result = try ProcessRunner.run(argv)
        guard allowFailure || result.status == 0 else {
            throw AugurError.git(
                command: arguments.joined(separator: " "),
                status: result.status,
                stderr: result.errorOutput
            )
        }
        return result.output
    }
}

// MARK: - Process Runner

/// Spawns a child process via `posix_spawn` and reaps it with a synchronous
/// `waitpid`, capturing stdout and stderr through temporary files.
///
/// This deliberately avoids `Foundation.Process`. On Linux, `Foundation.Process`
/// monitors child termination asynchronously and can miss a fast-exiting child
/// (e.g. `git rev-parse`), leaving `waitUntilExit()` blocked forever; the failure
/// surfaces most often when the tool is driven from within a test process. A
/// synchronous `waitpid` reaps the child itself, so it cannot miss the exit, and
/// the behaviour is identical on macOS and Linux.
internal enum ProcessRunner {
    internal struct Result: Sendable {
        internal let status: Int32
        internal let output: String
        internal let errorOutput: String
    }

    /// Runs `/usr/bin/env <argv>` with stdout and stderr captured, so a failing
    /// child's diagnostic (e.g. git's `fatal: ...`) can be surfaced to the user.
    internal static func run(_ argv: [String]) throws -> Result {
        let base = NSTemporaryDirectory() as NSString
        let token = UUID().uuidString
        let outputPath = base.appendingPathComponent("augur-git-\(token)")
        let errorPath = base.appendingPathComponent("augur-git-err-\(token)")
        FileManager.default.createFile(atPath: outputPath, contents: nil)
        FileManager.default.createFile(atPath: errorPath, contents: nil)
        defer {
            try? FileManager.default.removeItem(atPath: outputPath)
            try? FileManager.default.removeItem(atPath: errorPath)
        }

        let executable = "/usr/bin/env"
        let fullArgv = [executable] + argv

        // `posix_spawn_file_actions_t` is a struct on Glibc but an opaque pointer
        // on Darwin, so it must be declared differently per platform; both are
        // allocated by `posix_spawn_file_actions_init`.
        #if canImport(Darwin)
        var fileActions: posix_spawn_file_actions_t?
        #else
        var fileActions = posix_spawn_file_actions_t()
        #endif
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        posix_spawn_file_actions_addopen(&fileActions, 1, outputPath, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        posix_spawn_file_actions_addopen(&fileActions, 2, errorPath, O_WRONLY | O_CREAT | O_TRUNC, 0o644)

        let cArgs: [UnsafeMutablePointer<CChar>?] = fullArgv.map { strdup($0) } + [nil]
        defer { for case let arg? in cArgs { free(arg) } }

        // Pass the current environment (so `/usr/bin/env` finds git on PATH),
        // built from ProcessInfo to stay clear of the `environ` global, which
        // Swift does not expose uniformly across Darwin and Linux.
        let cEnv: [UnsafeMutablePointer<CChar>?] =
            ProcessInfo.processInfo.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { for case let entry? in cEnv { free(entry) } }

        var pid: pid_t = 0
        let spawnResult = posix_spawn(&pid, executable, &fileActions, nil, cArgs, cEnv)
        guard spawnResult == 0 else {
            throw AugurError.git(command: argv.joined(separator: " "), status: spawnResult, stderr: "")
        }

        var rawStatus: Int32 = 0
        while waitpid(pid, &rawStatus, 0) == -1 && errno == EINTR { continue }
        let status: Int32 = (rawStatus & 0x7f) == 0 ? (rawStatus >> 8) & 0xff : rawStatus & 0x7f

        let data = (try? Data(contentsOf: URL(fileURLWithPath: outputPath))) ?? Data()
        let errorData = (try? Data(contentsOf: URL(fileURLWithPath: errorPath))) ?? Data()
        return Result(
            status: status,
            output: String(decoding: data, as: UTF8.self),
            errorOutput: String(decoding: errorData, as: UTF8.self)
        )
    }
}
