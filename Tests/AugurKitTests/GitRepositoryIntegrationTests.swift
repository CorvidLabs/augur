@preconcurrency import Foundation
import XCTest
@testable import AugurKit

/// End-to-end coverage of the real `GitRepository` probe against a throwaway git
/// repository on disk. These tests drive the actual `git` CLI, so they prove the
/// byte-level format handling (`--numstat -z`, `core.quotepath=false`) that the
/// unit parsers can only assume. They are the source of truth for the rename and
/// non-ASCII path guarantees.
final class GitRepositoryIntegrationTests: XCTestCase {

    // MARK: - Rename resolution

    /// A renamed file (with a small content tweak detected as a rename) must
    /// resolve to its NEW path, not git's synthetic `{old => new}` brace string.
    func testRenamedFileResolvesToNewPath() throws {
        let repo = try TempGitRepo()
        defer { repo.cleanup() }
        // Large file so a one-line tweak stays above git's rename similarity threshold.
        var body = "package main\n"
        for index in 1...30 { body += "func f\(index)() { println(\(index)) }\n" }
        try repo.write("src/old.go", body)
        try repo.commit("init")
        try repo.run(["mv", "src/old.go", "src/new.go"])
        try repo.write("src/new.go", body.replacingOccurrences(of: "func f1()", with: "func renamed()"))
        try repo.commit("rename with tweak")

        let probe = GitRepository(path: repo.path)
        let files = try probe.changedFiles(in: .range("HEAD~1..HEAD"))
        XCTAssertEqual(files.map { $0.path }, ["src/new.go"])
        XCTAssertFalse(files[0].path.contains("=>"), "path must not be the synthetic brace string")
    }

    /// A pure rename (no content change) resolves to the new path with zero churn,
    /// so it scores as low-risk rather than as a large new file.
    func testPureRenameResolvesToNewPathWithZeroChurn() throws {
        let repo = try TempGitRepo()
        defer { repo.cleanup() }
        var body = "package main\n"
        for index in 1...30 { body += "func f\(index)() {}\n" }
        try repo.write("a.go", body)
        try repo.commit("init")
        try repo.run(["mv", "a.go", "b.go"])
        try repo.commit("pure rename")

        let probe = GitRepository(path: repo.path)
        let files = try probe.changedFiles(in: .range("HEAD~1..HEAD"))
        XCTAssertEqual(files.map { $0.path }, ["b.go"])
        XCTAssertEqual(files[0].churnLines, 0)
        XCTAssertFalse(files[0].path.contains("=>"))
    }

    // MARK: - Non-ASCII paths

    /// A non-ASCII filename must round-trip verbatim (not octal-quoted) so that
    /// CODEOWNERS matching finds the real owner.
    func testUnicodePathRoundTripsAndCodeOwnersMatches() throws {
        let repo = try TempGitRepo()
        defer { repo.cleanup() }
        try repo.write("café.go", "package main\nfunc cafe() {}\n")
        try repo.write("CODEOWNERS", "* @defaultowner\ncafé.go @cafeteam\n")
        try repo.commit("init")
        try repo.write("café.go", "package main\nfunc cafe() {}\nfunc more() {}\n")
        try repo.commit("change café")

        let probe = GitRepository(path: repo.path)
        let files = try probe.changedFiles(in: .range("HEAD~1..HEAD"))
        // Verbatim UTF-8 path, never `"caf\303\251.go"`.
        XCTAssertEqual(files.map { $0.path }, ["café.go"])

        let owners = CodeOwners.parse(try repo.read("CODEOWNERS"))
        XCTAssertEqual(owners.owners(for: files[0].path), ["@cafeteam"], "the café rule must match the real path")
    }

    /// `addedLines` (driven by `git diff --unified=0`) must key its results by the
    /// verbatim non-ASCII path so per-line coverage and SARIF line ranges line up.
    func testUnicodePathAddedLinesUseVerbatimPath() throws {
        let repo = try TempGitRepo()
        defer { repo.cleanup() }
        try repo.write("café.go", "package main\n")
        try repo.commit("init")
        try repo.write("café.go", "package main\nfunc more() {}\nfunc again() {}\n")
        try repo.commit("grow café")

        let probe = GitRepository(path: repo.path)
        let added = try probe.addedLines(in: .range("HEAD~1..HEAD"))
        XCTAssertEqual(added["café.go"], [2, 3])
    }

    // MARK: - Untracked files

    /// A brand-new, never-`git add`ed file must appear in a working-tree
    /// assessment as a fully-added file; invisibility would let a risk gate
    /// score an untracked change as zero risk.
    func testUntrackedFileAppearsInWorkingTreeScope() throws {
        let repo = try TempGitRepo()
        defer { repo.cleanup() }
        try repo.write("a.go", "package main\n")
        try repo.commit("init")
        try repo.write("src/new.swift", "public struct New {\n    public let value: Int\n}\n")

        let probe = GitRepository(path: repo.path)
        let files = try probe.changedFiles(in: .workingTree)
        let file = try XCTUnwrap(files.first { $0.path == "src/new.swift" }, "untracked file must be assessed")
        XCTAssertEqual(file.linesAdded, 3)
        XCTAssertEqual(file.linesDeleted, 0)
        XCTAssertFalse(file.isBinary)
        XCTAssertEqual(file.addedLines, [1, 2, 3], "every line of a new file is an added line")
    }

    /// Untracked files belong only to the working-tree scope: staged and range
    /// diffs are exact and must not gain phantom files.
    func testUntrackedFileAbsentFromStagedAndRangeScopes() throws {
        let repo = try TempGitRepo()
        defer { repo.cleanup() }
        try repo.write("a.go", "package main\n")
        try repo.commit("init")
        try repo.write("a.go", "package main\nfunc f() {}\n")
        try repo.commit("change")
        try repo.write("untracked.swift", "let x = 1\n")

        let probe = GitRepository(path: repo.path)
        let staged = try probe.changedFiles(in: .staged)
        XCTAssertFalse(staged.contains { $0.path == "untracked.swift" })
        let ranged = try probe.changedFiles(in: .range("HEAD~1..HEAD"))
        XCTAssertFalse(ranged.contains { $0.path == "untracked.swift" })
    }

    /// `.gitignore`d files are not part of the change surface (`--exclude-standard`).
    func testGitignoredFileStaysInvisible() throws {
        let repo = try TempGitRepo()
        defer { repo.cleanup() }
        try repo.write(".gitignore", "ignored.log\n")
        try repo.commit("init")
        try repo.write("ignored.log", "noise\n")

        let probe = GitRepository(path: repo.path)
        let files = try probe.changedFiles(in: .workingTree)
        XCTAssertFalse(files.contains { $0.path == "ignored.log" })
    }

    /// An untracked binary blob is flagged binary with no line data.
    func testUntrackedBinaryFileIsFlaggedBinary() throws {
        let repo = try TempGitRepo()
        defer { repo.cleanup() }
        try repo.write("a.go", "package main\n")
        try repo.commit("init")
        let blobPath = (repo.path as NSString).appendingPathComponent("asset.bin")
        try Data([0x00, 0x01, 0x02, 0xFF, 0x00]).write(to: URL(fileURLWithPath: blobPath))

        let probe = GitRepository(path: repo.path)
        let files = try probe.changedFiles(in: .workingTree)
        let file = try XCTUnwrap(files.first { $0.path == "asset.bin" })
        XCTAssertTrue(file.isBinary)
        XCTAssertEqual(file.linesAdded, 0)
        XCTAssertTrue(file.addedLines.isEmpty)
    }

    /// `addedLines(in:)` (used for SARIF regions) covers untracked files too.
    func testUntrackedFileAppearsInAddedLinesQuery() throws {
        let repo = try TempGitRepo()
        defer { repo.cleanup() }
        try repo.write("a.go", "package main\n")
        try repo.commit("init")
        try repo.write("fresh.swift", "let a = 1\nlet b = 2\n")

        let probe = GitRepository(path: repo.path)
        let added = try probe.addedLines(in: .workingTree)
        XCTAssertEqual(added["fresh.swift"], [1, 2])
    }

    // MARK: - Git failure diagnostics

    /// A failing git invocation must surface git's own stderr (e.g. `fatal:
    /// ambiguous argument`), not just a bare exit code.
    func testGitFailureSurfacesStderr() throws {
        let repo = try TempGitRepo()
        defer { repo.cleanup() }
        try repo.write("a.go", "package main\n")
        try repo.commit("init")

        let probe = GitRepository(path: repo.path)
        XCTAssertThrowsError(try probe.changedFiles(in: .range("nonsense..HEAD"))) { error in
            guard case AugurError.git(let command, let status, let stderr) = error else {
                return XCTFail("expected AugurError.git, got \(error)")
            }
            XCTAssertEqual(status, 128)
            XCTAssertTrue(command.contains("nonsense..HEAD"))
            XCTAssertTrue(stderr.contains("nonsense"), "stderr must carry git's diagnostic, got: \(stderr)")
            let description = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(description.contains("fatal"), "the rendered error must include git's message, got: \(description)")
        }
    }

    // MARK: - Exclude matching

    /// A non-ASCII path must be matchable by an exclude glob (it was unreachable
    /// when the path arrived octal-quoted).
    func testUnicodePathIsExcludable() throws {
        let repo = try TempGitRepo()
        defer { repo.cleanup() }
        try repo.write("naïve/data.go", "package main\n")
        try repo.commit("init")
        try repo.write("naïve/data.go", "package main\nvar x = 1\n")
        try repo.commit("change")

        let probe = GitRepository(path: repo.path)
        let files = try probe.changedFiles(in: .range("HEAD~1..HEAD"))
        let filter = PathFilter(globs: ["naïve/**"])
        XCTAssertTrue(files.allSatisfy { filter.excludes($0.path) }, "the unicode path must be excludable")
    }
}

// MARK: - Temp git repo helper

/// A disposable git repository under the system temp directory for integration
/// tests. Configured with a local identity and no GPG signing so commits succeed
/// in any environment.
private struct TempGitRepo {
    let path: String

    init() throws {
        let base = NSTemporaryDirectory()
        path = (base as NSString).appendingPathComponent("augur-it-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        try run(["init", "-q"])
        try run(["config", "user.email", "test@augur.test"])
        try run(["config", "user.name", "Augur Test"])
        try run(["config", "commit.gpgsign", "false"])
    }

    func cleanup() {
        try? FileManager.default.removeItem(atPath: path)
    }

    /// Writes `contents` to `relativePath`, creating intermediate directories.
    func write(_ relativePath: String, _ contents: String) throws {
        let full = (path as NSString).appendingPathComponent(relativePath)
        let directory = (full as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try contents.write(toFile: full, atomically: true, encoding: .utf8)
    }

    /// Reads `relativePath` as UTF-8 text.
    func read(_ relativePath: String) throws -> String {
        let full = (path as NSString).appendingPathComponent(relativePath)
        return try String(contentsOfFile: full, encoding: .utf8)
    }

    /// Stages everything and commits with `message`.
    func commit(_ message: String) throws {
        try run(["add", "-A"])
        try run(["commit", "-q", "-m", message])
    }

    /// Runs a git subcommand in the repo, throwing on a non-zero exit.
    ///
    /// Delegates to AugurKit's `ProcessRunner` (posix_spawn + synchronous waitpid)
    /// rather than `Foundation.Process`, which deadlocks under swift-corelibs on
    /// Linux when a fast-exiting child's termination is missed.
    @discardableResult
    func run(_ arguments: [String]) throws -> String {
        let result = try ProcessRunner.run(["git", "-C", path] + arguments)
        guard result.status == 0 else {
            throw NSError(
                domain: "TempGitRepo",
                code: Int(result.status),
                userInfo: [NSLocalizedDescriptionKey: "git \(arguments.joined(separator: " ")) failed"]
            )
        }
        return result.output
    }
}
