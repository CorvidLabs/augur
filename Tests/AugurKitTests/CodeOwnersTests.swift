import XCTest
@testable import AugurKit

final class CodeOwnersTests: XCTestCase {

    // MARK: - Parsing

    func testCommentsAndBlankLinesIgnored() {
        let owners = CodeOwners.parse("""
        # This is a comment
        \t# indented comment

        *.swift   @swift-team

        """)
        XCTAssertEqual(owners.rules.count, 1)
        XCTAssertEqual(owners.rules.first?.owners, ["@swift-team"])
    }

    func testMultipleOwnersOnALine() {
        let owners = CodeOwners.parse("/src/  @alice @bob @org/team carol@example.com")
        XCTAssertEqual(owners.owners(for: "src/a.swift"), ["@alice", "@bob", "@org/team", "carol@example.com"])
    }

    func testTabSeparatedFields() {
        let owners = CodeOwners.parse("*.swift\t@swift\t@platform")
        XCTAssertEqual(owners.owners(for: "Sources/App/Main.swift"), ["@swift", "@platform"])
    }

    func testEmptyTextIsEmpty() {
        let owners = CodeOwners.parse("")
        XCTAssertTrue(owners.isEmpty)
        XCTAssertEqual(owners.owners(for: "anything.swift"), [])
    }

    // MARK: - Matching semantics

    func testGlobalCatchAllMatchesEverything() {
        let owners = CodeOwners.parse("* @global")
        XCTAssertEqual(owners.owners(for: "a.swift"), ["@global"])
        XCTAssertEqual(owners.owners(for: "deep/nested/path/file.kt"), ["@global"])
    }

    func testLastMatchWins() {
        let owners = CodeOwners.parse("""
        *            @global
        /src/        @src-team
        /src/auth/   @security
        """)
        XCTAssertEqual(owners.owners(for: "README.md"), ["@global"])
        XCTAssertEqual(owners.owners(for: "src/service.swift"), ["@src-team"])
        // The most specific (last) matching rule wins.
        XCTAssertEqual(owners.owners(for: "src/auth/token.swift"), ["@security"])
    }

    func testUnownedFileReturnsEmpty() {
        let owners = CodeOwners.parse("/docs/ @docs-team")
        XCTAssertEqual(owners.owners(for: "src/service.swift"), [])
    }

    func testEmptyOwnersUnsetsOwnership() {
        // A pattern with no owners explicitly clears ownership (last-match-wins).
        let owners = CodeOwners.parse("""
        *           @global
        /generated/
        """)
        XCTAssertEqual(owners.owners(for: "src/a.swift"), ["@global"])
        XCTAssertEqual(owners.owners(for: "generated/code.swift"), [])
    }

    func testBareNameMatchesAtAnyDepth() {
        let owners = CodeOwners.parse("*.swift @swift")
        XCTAssertEqual(owners.owners(for: "a.swift"), ["@swift"])
        XCTAssertEqual(owners.owners(for: "Sources/App/Deep/File.swift"), ["@swift"])
        XCTAssertEqual(owners.owners(for: "a.kt"), [])
    }

    func testDirectoryPatternMatchesContents() {
        let owners = CodeOwners.parse("/docs/ @docs-team")
        XCTAssertEqual(owners.owners(for: "docs/guide.md"), ["@docs-team"])
        XCTAssertEqual(owners.owners(for: "docs/sub/deep.md"), ["@docs-team"])
        XCTAssertEqual(owners.owners(for: "src/docs.md"), [])
    }

    func testRootedPathGlob() {
        let owners = CodeOwners.parse("/src/*.swift @top")
        XCTAssertEqual(owners.owners(for: "src/a.swift"), ["@top"])
        // `*` does not cross a separator, so a nested file is not matched.
        XCTAssertEqual(owners.owners(for: "src/sub/a.swift"), [])
    }

    // MARK: - Sibling anchoring (regression: directory ownership must not leak)

    func testDirectoryRuleDoesNotOwnSiblingPrefixes() {
        // `/docs/` owns `docs/...` but must not own a sibling like `docs-internal/`.
        let owners = CodeOwners.parse("/docs/ @docs-team")
        XCTAssertEqual(owners.owners(for: "docs/x.md"), ["@docs-team"])
        XCTAssertEqual(owners.owners(for: "docs/sub/x.md"), ["@docs-team"])
        XCTAssertEqual(owners.owners(for: "docs-internal/x.md"), [])
        XCTAssertEqual(owners.owners(for: "docsite/x.md"), [])
    }

    func testSrcDirectoryRuleDoesNotOwnSiblingPrefixes() {
        let owners = CodeOwners.parse("/src/ @src-team")
        XCTAssertEqual(owners.owners(for: "src/a.go"), ["@src-team"])
        XCTAssertEqual(owners.owners(for: "src/deep/a.go"), ["@src-team"])
        XCTAssertEqual(owners.owners(for: "srcgen/a.go"), [])
        XCTAssertEqual(owners.owners(for: "src-old/a.go"), [])
    }

    func testStandardLocationsOrder() {
        XCTAssertEqual(CodeOwners.standardLocations, [".github/CODEOWNERS", "CODEOWNERS", "docs/CODEOWNERS"])
    }
}
