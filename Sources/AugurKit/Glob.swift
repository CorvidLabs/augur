@preconcurrency import Foundation

// MARK: - Glob Pattern

/// A compiled glob pattern matched against forward-slash paths.
///
/// Supported syntax (the common, portable subset):
///  - `*` matches any run of characters **except** the path separator `/`.
///  - `**` matches any run of characters **including** `/` (recursive).
///  - `?` matches exactly one character (including `/`).
///  - All other characters match literally.
///
/// Patterns are anchored to the whole path: `vendor` matches only the literal
/// path `vendor`, while `vendor/**` matches everything beneath `vendor/`. Use a
/// trailing `/**` (or a leading `**/`) to match a directory's contents anywhere.
///
/// Matching is purely structural (Foundation-only, no third-party dependency)
/// and deterministic. Compilation lowers the glob to an `NSRegularExpression`.
public struct GlobPattern: Sendable, Equatable {
    /// The original glob text, preserved for diagnostics and equality.
    public let pattern: String
    private let regex: String

    /// Compiles a glob pattern. Compilation never fails: invalid regex fragments
    /// cannot arise because every metacharacter is escaped during translation.
    /// - Parameter pattern: The glob text (e.g. `vendor/**`, `**/*.generated.swift`).
    public init(_ pattern: String) {
        self.pattern = pattern
        self.regex = Self.translate(pattern)
    }

    /// Whether the pattern matches the given path. The path is normalized so a
    /// leading `./` and any duplicate or trailing slashes do not defeat matching.
    /// - Parameter path: A forward-slash path (e.g. `vendor/lib/x.swift`).
    /// - Returns: `true` when the whole normalized path matches the pattern.
    public func matches(_ path: String) -> Bool {
        let normalized = Self.normalize(path)
        guard let expression = try? NSRegularExpression(pattern: regex) else { return false }
        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        return expression.firstMatch(in: normalized, range: range) != nil
    }

    // MARK: - Translation

    /// Lowers a glob to an anchored regular-expression source string.
    ///
    /// Every `**` is translated so its match is anchored at a `/` boundary, never
    /// mid-segment, so `vendor/**` cannot leak onto sibling paths like `vendors/x`
    /// or `vendorize.go`. The recognized recursive tokens are:
    ///  - A trailing or mid-path `/**` becomes `(/.*)?`: an optional, slash-rooted
    ///    remainder. So `vendor/**` matches `vendor` and `vendor/a/b`, but not
    ///    `vendors/x`; `a/**/b` matches `a/b` and `a/x/y/b`.
    ///  - A leading or mid-path `**/` becomes `(.*/)?`: an optional, slash-ended
    ///    prefix. So `**/foo` matches `foo` and `a/b/foo`, but not `barfoo`.
    ///  - A bare `**` (no adjacent separator) becomes `.*`.
    ///
    /// A run of three or more consecutive `*` is collapsed to a single `**` so a
    /// pathological pattern like `a/****/b` is well defined. Single `*` matches any
    /// run except `/`; every literal run is regex-escaped.
    static func translate(_ glob: String) -> String {
        var out = "\\A"
        let scalars = Array(glob)
        var index = 0
        while index < scalars.count {
            let character = scalars[index]
            switch character {
            case "/":
                // A `/**` token (slash + double-star) is the recursive descent of a
                // directory: anchor the optional remainder at the `/` boundary so the
                // match cannot bleed onto sibling names. `vendor/**` -> `vendor(/.*)?`.
                let runAfterSlash = starRun(scalars, at: index + 1)
                if runAfterSlash >= 2 {
                    // `(/.*)?` is the optional slash-rooted remainder. Any following
                    // separator stays literal, so `a/**/b` becomes `a(/.*)?/b`, which
                    // matches `a/b` and `a/x/y/b` but never `ab`.
                    out += "(/.*)?"
                    index += 1 + runAfterSlash
                } else {
                    out += "/"
                    index += 1
                }
            case "*":
                let run = starRun(scalars, at: index)
                if run >= 2 {
                    index += run
                    // A `**/` prefix is an optional, slash-ended run of segments so it
                    // also matches zero segments (`**/x` matches the bare `x`) without
                    // leaking mid-segment (`**/foo` does not match `barfoo`).
                    if index < scalars.count, scalars[index] == "/" {
                        out += "(.*/)?"
                        index += 1
                    } else {
                        // A bare `**`: any characters including the separator.
                        out += ".*"
                    }
                } else {
                    // `*` — any characters except the separator.
                    out += "[^/]*"
                    index += 1
                }
            case "?":
                out += "."
                index += 1
            default:
                out += Self.escape(character)
                index += 1
            }
        }
        out += "\\z"
        return out
    }

    /// Counts the run of consecutive `*` characters starting at `index`.
    /// - Parameters:
    ///   - scalars: The glob characters.
    ///   - index: The starting offset.
    /// - Returns: The number of `*` characters at `index` (0 if none).
    private static func starRun(_ scalars: [Character], at index: Int) -> Int {
        var count = 0
        var cursor = index
        while cursor < scalars.count, scalars[cursor] == "*" {
            count += 1
            cursor += 1
        }
        return count
    }

    /// Escapes a single character for safe inclusion in a regular expression.
    private static func escape(_ character: Character) -> String {
        let specials: Set<Character> = [".", "+", "(", ")", "|", "[", "]", "{", "}", "^", "$", "\\"]
        return specials.contains(character) ? "\\\(character)" : String(character)
    }

    /// Normalizes a path for matching: strips a leading `./`, collapses repeated
    /// slashes, and drops a trailing slash (but preserves the bare root `/`).
    static func normalize(_ path: String) -> String {
        var result = path
        while result.hasPrefix("./") {
            result.removeFirst(2)
        }
        while result.contains("//") {
            result = result.replacingOccurrences(of: "//", with: "/")
        }
        if result.count > 1, result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }
}

// MARK: - Path Filter

/// A set of glob patterns used to drop paths from an assessment.
///
/// A `PathFilter` is the exclusion lens applied in `Augur.assess(...)`: a changed
/// file is removed before scoring when any of its patterns match. An empty filter
/// excludes nothing, so it is behavior-preserving when no patterns are configured.
public struct PathFilter: Sendable, Equatable {
    /// The exclusion patterns, in their configured order.
    public let patterns: [GlobPattern]

    /// Creates a filter from already-compiled patterns.
    /// - Parameter patterns: The exclusion globs.
    public init(patterns: [GlobPattern]) {
        self.patterns = patterns
    }

    /// Creates a filter from raw glob strings.
    /// - Parameter globs: The exclusion glob texts.
    public init(globs: [String]) {
        self.patterns = globs.map { GlobPattern($0) }
    }

    /// Whether this filter has no patterns (and therefore excludes nothing).
    public var isEmpty: Bool { patterns.isEmpty }

    /// Whether the path should be excluded (matches any pattern).
    /// - Parameter path: A forward-slash path.
    /// - Returns: `true` when at least one pattern matches.
    public func excludes(_ path: String) -> Bool {
        patterns.contains { $0.matches(path) }
    }
}
