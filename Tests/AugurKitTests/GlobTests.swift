import XCTest
@testable import AugurKit

final class GlobTests: XCTestCase {

    // MARK: - Single star

    func testStarMatchesWithinSegment() {
        let pattern = GlobPattern("*.swift")
        XCTAssertTrue(pattern.matches("Service.swift"))
        XCTAssertTrue(pattern.matches("a.swift"))
        XCTAssertFalse(pattern.matches("Service.kt"))
    }

    func testStarDoesNotCrossSeparator() {
        let pattern = GlobPattern("src/*.swift")
        XCTAssertTrue(pattern.matches("src/Service.swift"))
        XCTAssertFalse(pattern.matches("src/sub/Service.swift"))
    }

    func testStarAnchoredWholePath() {
        let pattern = GlobPattern("vendor")
        XCTAssertTrue(pattern.matches("vendor"))
        XCTAssertFalse(pattern.matches("vendor/x"))
        XCTAssertFalse(pattern.matches("a/vendor"))
    }

    // MARK: - Double star

    func testDoubleStarCrossesSeparators() {
        let pattern = GlobPattern("vendor/**")
        XCTAssertTrue(pattern.matches("vendor/lib/x.swift"))
        XCTAssertTrue(pattern.matches("vendor/a"))
        XCTAssertTrue(pattern.matches("vendor/a/b/c/d.swift"))
        XCTAssertFalse(pattern.matches("src/vendor/x"))
    }

    func testDoubleStarMatchesZeroSegments() {
        // `vendor/**` should also match the bare directory `vendor`.
        let pattern = GlobPattern("vendor/**")
        XCTAssertTrue(pattern.matches("vendor"))
    }

    func testLeadingDoubleStarMatchesAnywhere() {
        let pattern = GlobPattern("**/*.generated.swift")
        XCTAssertTrue(pattern.matches("Sources/App/Model.generated.swift"))
        XCTAssertTrue(pattern.matches("Model.generated.swift"))
        XCTAssertTrue(pattern.matches("a/b/c/X.generated.swift"))
        XCTAssertFalse(pattern.matches("Sources/App/Model.swift"))
    }

    func testNodeModulesDirectoryGlob() {
        let pattern = GlobPattern("node_modules/**")
        XCTAssertTrue(pattern.matches("node_modules/react/index.js"))
        XCTAssertFalse(pattern.matches("src/node_modules_helper.js"))
    }

    // MARK: - Sibling anchoring (regression: dir/** must not leak onto siblings)

    func testDirectoryGlobDoesNotMatchSiblingPrefixes() {
        // `vendor/**` must match the directory and its contents, but never a
        // sibling path that merely shares the `vendor` prefix.
        let pattern = GlobPattern("vendor/**")
        XCTAssertTrue(pattern.matches("vendor"))
        XCTAssertTrue(pattern.matches("vendor/x"))
        XCTAssertTrue(pattern.matches("vendor/a/b"))
        XCTAssertFalse(pattern.matches("vendors/x"))
        XCTAssertFalse(pattern.matches("vendorize.go"))
        XCTAssertFalse(pattern.matches("vendor-old/y"))
    }

    func testDocsGlobDoesNotMatchSiblingPrefixes() {
        let pattern = GlobPattern("docs/**")
        XCTAssertTrue(pattern.matches("docs"))
        XCTAssertTrue(pattern.matches("docs/guide.md"))
        XCTAssertTrue(pattern.matches("docs/a/b/x.md"))
        XCTAssertFalse(pattern.matches("docs-internal/secret.md"))
        XCTAssertFalse(pattern.matches("docsite/x.md"))
    }

    func testSrcGlobDoesNotMatchSiblingPrefixes() {
        let pattern = GlobPattern("src/**")
        XCTAssertTrue(pattern.matches("src"))
        XCTAssertTrue(pattern.matches("src/main.go"))
        XCTAssertTrue(pattern.matches("src/deep/main.go"))
        XCTAssertFalse(pattern.matches("srcgen/a.go"))
        XCTAssertFalse(pattern.matches("src-old/a.go"))
    }

    func testLeadingDoubleStarDoesNotMatchMidSegment() {
        // `**/foo` is anchored at a `/` boundary, so `barfoo` must not match.
        let pattern = GlobPattern("**/foo")
        XCTAssertTrue(pattern.matches("foo"))
        XCTAssertTrue(pattern.matches("a/foo"))
        XCTAssertTrue(pattern.matches("a/b/foo"))
        XCTAssertFalse(pattern.matches("barfoo"))
        XCTAssertFalse(pattern.matches("a/barfoo"))
    }

    func testMiddleDoubleStarMatchesZeroOrMoreSegments() {
        let pattern = GlobPattern("a/**/b")
        XCTAssertTrue(pattern.matches("a/b"))
        XCTAssertTrue(pattern.matches("a/x/b"))
        XCTAssertTrue(pattern.matches("a/x/y/b"))
        XCTAssertFalse(pattern.matches("ab"))
        XCTAssertFalse(pattern.matches("a/bc"))
        XCTAssertFalse(pattern.matches("ax/b"))
    }

    func testBareDoubleStarStillMatchesEverything() {
        let pattern = GlobPattern("**")
        XCTAssertTrue(pattern.matches("x"))
        XCTAssertTrue(pattern.matches("a/b/c"))
        XCTAssertTrue(pattern.matches(""))
    }

    // MARK: - Question mark

    func testQuestionMarkSingleCharacter() {
        let pattern = GlobPattern("file?.txt")
        XCTAssertTrue(pattern.matches("file1.txt"))
        XCTAssertTrue(pattern.matches("fileA.txt"))
        XCTAssertFalse(pattern.matches("file.txt"))
        XCTAssertFalse(pattern.matches("file12.txt"))
    }

    // MARK: - Literal / regex-special escaping

    func testDotIsLiteral() {
        let pattern = GlobPattern("a.b")
        XCTAssertTrue(pattern.matches("a.b"))
        XCTAssertFalse(pattern.matches("axb"))
    }

    func testRegexSpecialsAreEscaped() {
        let pattern = GlobPattern("pkg(v1)/x+y.swift")
        XCTAssertTrue(pattern.matches("pkg(v1)/x+y.swift"))
        XCTAssertFalse(pattern.matches("pkgv1/xy.swift"))
    }

    // MARK: - Normalization

    func testNormalizationStripsLeadingDotSlash() {
        let pattern = GlobPattern("src/*.swift")
        XCTAssertTrue(pattern.matches("./src/Service.swift"))
    }

    // MARK: - Lockfile example

    func testLockfileGlob() {
        let pattern = GlobPattern("**/Package.resolved")
        XCTAssertTrue(pattern.matches("Package.resolved"))
        XCTAssertTrue(pattern.matches("a/b/Package.resolved"))
        XCTAssertFalse(pattern.matches("Package.swift"))
    }

    // MARK: - PathFilter

    func testPathFilterExcludesAnyMatch() {
        let filter = PathFilter(globs: ["vendor/**", "**/*.generated.swift"])
        XCTAssertTrue(filter.excludes("vendor/lib/x.swift"))
        XCTAssertTrue(filter.excludes("Sources/App/Model.generated.swift"))
        XCTAssertFalse(filter.excludes("Sources/App/Model.swift"))
    }

    func testEmptyPathFilterExcludesNothing() {
        let filter = PathFilter(globs: [])
        XCTAssertTrue(filter.isEmpty)
        XCTAssertFalse(filter.excludes("anything/at/all.swift"))
    }

    // MARK: - Pathological / robustness

    func testEmptyPatternMatchesOnlyEmptyPath() {
        let pattern = GlobPattern("")
        XCTAssertTrue(pattern.matches(""))
        XCTAssertFalse(pattern.matches("a"))
    }

    func testBareDoubleStarMatchesEverything() {
        let pattern = GlobPattern("**")
        XCTAssertTrue(pattern.matches("a"))
        XCTAssertTrue(pattern.matches("a/b/c.swift"))
        XCTAssertTrue(pattern.matches(""))
    }

    func testManyConsecutiveStarsDoNotCrash() {
        // A pathological run of stars must still compile and match deterministically.
        let pattern = GlobPattern("a/****/b")
        XCTAssertTrue(pattern.matches("a/x/y/b"))
        XCTAssertTrue(pattern.matches("a/b"))
    }

    func testPatternIsWholePathAnchoredNotSubstring() {
        let pattern = GlobPattern("auth")
        XCTAssertTrue(pattern.matches("auth"))
        XCTAssertFalse(pattern.matches("src/auth/token.swift"))
        XCTAssertFalse(pattern.matches("oauth"))
    }

    func testNestedBracesAndPipesAreLiteral() {
        let pattern = GlobPattern("a{b|c}.swift")
        XCTAssertTrue(pattern.matches("a{b|c}.swift"))
        XCTAssertFalse(pattern.matches("ab.swift"))
    }

    func testTrailingSlashNormalized() {
        let pattern = GlobPattern("src/lib")
        XCTAssertTrue(pattern.matches("src/lib/"))
        XCTAssertTrue(pattern.matches("src/lib"))
    }

    // MARK: - CODEOWNERS pattern compilation

    func testCodeOwnersCatchAllCompilesToDoubleStar() {
        XCTAssertEqual(CodeOwners.compile(pattern: "*").pattern, "**")
    }

    func testCodeOwnersRootedDirectoryCompiles() {
        let glob = CodeOwners.compile(pattern: "/docs/")
        XCTAssertTrue(glob.matches("docs/guide.md"))
        XCTAssertTrue(glob.matches("docs/sub/x.md"))
        XCTAssertFalse(glob.matches("src/docs/x.md"))
    }

    func testCodeOwnersBareExtensionMatchesAnyDepth() {
        let glob = CodeOwners.compile(pattern: "*.swift")
        XCTAssertTrue(glob.matches("a.swift"))
        XCTAssertTrue(glob.matches("Sources/Deep/B.swift"))
        XCTAssertFalse(glob.matches("a.kt"))
    }
}
