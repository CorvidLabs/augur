@preconcurrency import Foundation

// MARK: - CodeOwners

/// A parsed `CODEOWNERS` file, mapping changed paths to their declared owners.
///
/// `CODEOWNERS` assigns review ownership to paths using gitignore-like glob
/// rules. Each non-comment, non-blank line is a pattern followed by one or more
/// owners (`@user`, `@org/team`, or an email):
///
/// ```text
/// # comment
/// *            @global-owner
/// /docs/       @docs-team
/// *.swift      @swift-team @platform
/// ```
///
/// Per GitHub semantics the **last** matching rule wins, so later, more specific
/// rules override earlier ones. A line with a pattern but no owners explicitly
/// *unsets* ownership for that pattern (still last-match-wins).
///
/// Matching reuses the engine's `GlobPattern`, so it is Foundation-only and has
/// no third-party dependency. `CODEOWNERS` directory and anchoring conventions
/// are normalized to `GlobPattern` syntax during parsing (see `compile(pattern:)`).
public struct CodeOwners: Sendable, Equatable {
    /// One parsed rule: a compiled pattern and its declared owners (possibly empty).
    public struct Rule: Sendable, Equatable {
        /// The compiled glob used to match changed paths.
        public let pattern: GlobPattern
        /// The original pattern text as written in the file (for diagnostics).
        public let source: String
        /// The declared owners (`@user` / `@org/team` / email); empty unsets ownership.
        public let owners: [String]

        public init(pattern: GlobPattern, source: String, owners: [String]) {
            self.pattern = pattern
            self.source = source
            self.owners = owners
        }
    }

    /// The parsed rules, in file order (top to bottom). Later rules win.
    public let rules: [Rule]

    /// The standard repository locations a `CODEOWNERS` file may live, in the
    /// precedence order GitHub uses (the first that exists wins).
    public static let standardLocations = [".github/CODEOWNERS", "CODEOWNERS", "docs/CODEOWNERS"]

    /// Creates a `CodeOwners` from already-parsed rules.
    /// - Parameter rules: The rules in file order.
    public init(rules: [Rule]) {
        self.rules = rules
    }

    /// Whether the file declared no rules (so every path is unowned).
    public var isEmpty: Bool { rules.isEmpty }

    // MARK: - Parsing

    /// Parses `CODEOWNERS` text into a `CodeOwners`.
    ///
    /// Comments (`#`) and blank lines are ignored. Each remaining line is split
    /// on whitespace into a pattern and zero or more owners. The pattern is
    /// translated to `GlobPattern` syntax (see `compile(pattern:)`).
    /// - Parameter text: The raw `CODEOWNERS` file contents.
    /// - Returns: The parsed owners model.
    public static func parse(_ text: String) -> CodeOwners {
        var rules: [Rule] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard let patternText = fields.first else { continue }
            let owners = Array(fields.dropFirst())
            let pattern = compile(pattern: patternText)
            rules.append(Rule(pattern: pattern, source: patternText, owners: owners))
        }
        return CodeOwners(rules: rules)
    }

    /// Translates a `CODEOWNERS` pattern into an equivalent `GlobPattern`.
    ///
    /// `CODEOWNERS` patterns are gitignore-like; this maps the common forms onto
    /// the engine's whole-path-anchored glob syntax:
    ///  - `*` (the catch-all) matches every path → `**`.
    ///  - A leading `/` anchors to the repo root; it is dropped (`GlobPattern` is
    ///    already whole-path anchored).
    ///  - A trailing `/` means a directory and everything beneath it → `dir/**`.
    ///  - A bare segment with no slash (e.g. `*.swift`, `build`) may appear at any
    ///    depth, so it is prefixed with `**/` and, for a directory, suffixed `/**`.
    ///  - Anything already containing a slash is treated as a rooted path glob.
    /// - Parameter pattern: The raw `CODEOWNERS` pattern.
    /// - Returns: A compiled `GlobPattern`.
    static func compile(pattern: String) -> GlobPattern {
        if pattern == "*" { return GlobPattern("**") }

        let isDirectory = pattern.hasSuffix("/")
        let isRooted = pattern.hasPrefix("/")
        var body = pattern
        if isRooted { body.removeFirst() }
        if isDirectory { body.removeLast() }
        guard !body.isEmpty else { return GlobPattern("**") }

        let hasSlash = body.contains("/")
        var glob: String
        if isRooted || hasSlash {
            // Rooted or already path-shaped: match it directly (whole-path anchored).
            glob = body
        } else {
            // A bare name matches at any directory depth.
            glob = "**/\(body)"
        }
        if isDirectory {
            glob += "/**"
        }
        return GlobPattern(glob)
    }

    // MARK: - Query

    /// The owners declared for a path, applying last-match-wins.
    ///
    /// All rules are checked in file order; the **last** rule whose pattern
    /// matches determines the result (an owner-less rule yields `[]`, explicitly
    /// unsetting ownership). A path matching no rule is unowned (`[]`).
    /// - Parameter path: A forward-slash changed-file path.
    /// - Returns: The owners for that path, or `[]` when unowned.
    public func owners(for path: String) -> [String] {
        var result: [String] = []
        for rule in rules where rule.pattern.matches(path) {
            result = rule.owners
        }
        return result
    }
}
