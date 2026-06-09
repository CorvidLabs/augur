@preconcurrency import Foundation

// MARK: - Probe Protocol

/// Read-only access to the facts `augur` needs from a repository.
///
/// Abstracted so the engine can be tested against an in-memory fixture without
/// shelling out to git.
public protocol RepositoryProbe: Sendable {
    /// Files touched in the given scope.
    func changedFiles(in scope: DiffScope) throws -> [ChangedFile]

    /// Recent commits (newest first), the basis for all history-derived signals.
    func recentCommits(limit: Int) throws -> [Commit]
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
        var args = ["diff", "--numstat"]
        switch scope {
        case .range(let range): args.append(range)
        case .staged: args.append("--cached")
        case .workingTree: args.append("HEAD")
        }
        let output = try run(args)
        return Self.parseNumstat(output)
    }

    public func recentCommits(limit: Int) throws -> [Commit] {
        // One log call powers churn, recency, ownership, coupling, and incidents.
        // Field separator: US (0x1f); record separator: a leading "\u{1e}".
        let format = "\u{1e}%H\u{1f}%ae\u{1f}%ct\u{1f}%s"
        let args = ["log", "-n", String(limit), "--no-merges", "--pretty=format:\(format)", "--name-only"]
        let output = try run(args, allowFailure: true)
        return Self.parseLog(output)
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
