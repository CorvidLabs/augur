@preconcurrency import Foundation
import AugurKit
import TOMLDecoder

// MARK: - Config Model

/// A decoded `.augur.toml`, parsed entirely in the CLI layer so `AugurKit`
/// stays free of any TOML / third-party dependency.
///
/// All sections are optional; an empty or absent file is equivalent to the
/// built-in defaults, so configuration is strictly additive and
/// behavior-preserving when omitted.
struct AugurConfig: Decodable, Sendable {
    struct ThresholdsConfig: Decodable, Sendable {
        var review: Double?
        var block: Double?
    }

    struct WeightsConfig: Decodable, Sendable {
        var sensitivity: Double?
        var testGap: Double?
        var churn: Double?
        var coupling: Double?
        var diffShape: Double?
        var ownership: Double?
        var incident: Double?
        var codeowners: Double?
    }

    struct RuleConfig: Decodable, Sendable {
        var label: String
        var risk: Double
        var fragments: [String]
    }

    struct SensitivityConfig: Decodable, Sendable {
        var replaceDefaults: Bool?
    }

    struct ExcludeConfig: Decodable, Sendable {
        var paths: [String]?
    }

    var thresholds: ThresholdsConfig?
    var weights: WeightsConfig?
    var rules: [RuleConfig]?
    var sensitivity: SensitivityConfig?
    var exclude: ExcludeConfig?

    // MARK: - Resolution

    /// The configured thresholds, falling back to the engine defaults per field.
    func resolvedThresholds() -> Thresholds {
        let base = Thresholds.default
        return Thresholds(
            review: thresholds?.review ?? base.review,
            block: thresholds?.block ?? base.block
        )
    }

    /// The configured signal weights, overriding only the fields present in the file.
    func resolvedWeights() -> RiskEngine.Weights {
        var weights = RiskEngine.Weights()
        guard let configured = self.weights else { return weights }
        if let value = configured.sensitivity { weights.sensitivity = value }
        if let value = configured.testGap { weights.testGap = value }
        if let value = configured.churn { weights.churn = value }
        if let value = configured.coupling { weights.coupling = value }
        if let value = configured.diffShape { weights.diffShape = value }
        if let value = configured.ownership { weights.ownership = value }
        if let value = configured.incident { weights.incident = value }
        if let value = configured.codeowners { weights.codeowners = value }
        return weights
    }

    /// The effective sensitivity ruleset: built-in defaults with custom rules
    /// appended, unless `[sensitivity] replace_defaults = true` is set, in which
    /// case only the custom rules apply.
    func resolvedRules() -> [SensitivityRule] {
        let custom = (rules ?? []).map {
            SensitivityRule(label: $0.label, risk: $0.risk, fragments: $0.fragments)
        }
        if sensitivity?.replaceDefaults == true {
            return custom
        }
        return SensitivityRuleset.default + custom
    }

    /// The configured exclusion globs (`[exclude] paths = [...]`), or `[]`.
    func resolvedExcludes() -> [String] {
        exclude?.paths ?? []
    }

    /// Builds a `RiskEngine` from this configuration.
    func makeEngine() -> RiskEngine {
        RiskEngine(weights: resolvedWeights(), rules: resolvedRules(), thresholds: resolvedThresholds())
    }
}

// MARK: - Unknown-Key Detection

/// A structural mirror of a TOML document: tables, arrays, and scalars.
///
/// `TOMLDecoder` silently ignores any key the target type does not declare, so a
/// typo'd security rule (`[[sensitivity.rules]]` instead of `[[rules]]`) would
/// fail open. Walking the raw `TOMLTable` exposes every key actually present so
/// it can be validated against the known schema.
internal enum TOMLShape: Sendable, Equatable {
    case table([String: TOMLShape])
    case array([TOMLShape])
    case scalar

    /// The shape of a raw TOML table. Inline values (including inline tables
    /// and value arrays) appear as `.scalar`, which the schema walk treats as
    /// "known here, not descended into" — never a false positive.
    internal static func shape(of table: TOMLTable) -> TOMLShape {
        var entries: [String: TOMLShape] = [:]
        for key in table.keys {
            if let child = try? table.table(forKey: key) {
                entries[key] = shape(of: child)
            } else if let child = try? table.array(forKey: key) {
                entries[key] = shape(of: child)
            } else {
                entries[key] = .scalar
            }
        }
        return .table(entries)
    }

    /// The shape of a raw TOML array (e.g. an `[[rules]]` array of tables).
    internal static func shape(of array: TOMLArray) -> TOMLShape {
        var elements: [TOMLShape] = []
        for index in 0..<array.count {
            if let child = try? array.table(atIndex: index) {
                elements.append(shape(of: child))
            } else if let child = try? array.array(atIndex: index) {
                elements.append(shape(of: child))
            } else {
                elements.append(.scalar)
            }
        }
        return .array(elements)
    }
}

/// The schema of keys `.augur.toml` understands, used to reject unknown keys so
/// a typo cannot silently disable configuration.
internal enum ConfigSchema {
    internal indirect enum Node: Sendable {
        case table([String: Node])
        case array(Node)
        case scalar
    }

    /// One unknown key found in a document: its dotted path and the valid keys
    /// at that level (for the error message).
    internal struct UnknownKey: Equatable, Sendable {
        internal let path: String
        internal let validKeys: [String]
    }

    /// Every key `.augur.toml` understands, in the snake_case the file uses.
    internal static let root: Node = .table([
        "thresholds": .table(["review": .scalar, "block": .scalar]),
        "weights": .table([
            "sensitivity": .scalar,
            "test_gap": .scalar,
            "churn": .scalar,
            "coupling": .scalar,
            "diff_shape": .scalar,
            "ownership": .scalar,
            "incident": .scalar,
            "codeowners": .scalar,
        ]),
        "rules": .array(.table(["label": .scalar, "risk": .scalar, "fragments": .array(.scalar)])),
        "sensitivity": .table(["replace_defaults": .scalar]),
        "exclude": .table(["paths": .array(.scalar)]),
    ])

    /// The unknown key paths in a document shape (e.g. `sensitivity.rules`),
    /// sorted for deterministic messages. Empty when every key is recognized.
    /// - Parameter shape: The document's structural shape.
    /// - Returns: The unknown keys with their valid siblings.
    internal static func unknownKeys(in shape: TOMLShape) -> [UnknownKey] {
        walk(shape, schema: root, path: "")
    }

    private static func walk(_ shape: TOMLShape, schema: Node, path: String) -> [UnknownKey] {
        switch (shape, schema) {
        case (.table(let entries), .table(let known)):
            var knownByNormalizedKey: [String: Node] = [:]
            for (key, node) in known { knownByNormalizedKey[normalize(key)] = node }
            var result: [UnknownKey] = []
            for (key, value) in entries.sorted(by: { $0.key < $1.key }) {
                let childPath = path.isEmpty ? key : "\(path).\(key)"
                if let childSchema = knownByNormalizedKey[normalize(key)] {
                    result += walk(value, schema: childSchema, path: childPath)
                } else {
                    result.append(UnknownKey(path: childPath, validKeys: known.keys.sorted()))
                }
            }
            return result
        case (.array(let elements), .array(let elementSchema)):
            var result: [UnknownKey] = []
            for (index, element) in elements.enumerated() {
                result += walk(element, schema: elementSchema, path: "\(path)[\(index)]")
            }
            return result
        default:
            // A shape/schema kind mismatch (e.g. a table where a number belongs)
            // is a type error; decoding reports it with a better message.
            return []
        }
    }

    /// Normalizes a key for comparison so `test_gap`, `testGap`, and `test-gap`
    /// all match the same schema entry.
    internal static func normalize(_ key: String) -> String {
        key.lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
    }
}

// MARK: - Loading

/// Loads and resolves `.augur.toml` configuration for the CLI.
enum ConfigLoader {
    /// The default config filename discovered at the repository root.
    static let defaultFilename = ".augur.toml"

    /// Decodes a config from TOML text.
    /// - Parameter text: The TOML document.
    /// - Returns: The decoded config.
    static func decode(text: String) throws -> AugurConfig {
        let decoder = TOMLDecoder(strategy: .init(key: .convertFromSnakeCase))
        return try decoder.decode(AugurConfig.self, from: text)
    }

    /// Parses the raw structural shape of a TOML document (keys verbatim,
    /// no snake-case conversion), for unknown-key detection.
    /// - Parameter text: The TOML document.
    /// - Returns: The document's shape.
    static func shape(of text: String) throws -> TOMLShape {
        TOMLShape.shape(of: try TOMLTable(source: text))
    }

    /// Throws `ConfigError.unknownKeys` when the document contains keys augur
    /// does not understand, so a typo'd rule cannot silently fail open.
    ///
    /// A document whose shape cannot be decoded at all is left to the main
    /// decode, which reports the parse error with a better message.
    /// - Parameters:
    ///   - text: The TOML document.
    ///   - path: The file path, for the error message.
    static func checkUnknownKeys(text: String, path: String) throws {
        guard let shape = try? shape(of: text) else { return }
        let unknown = ConfigSchema.unknownKeys(in: shape)
        guard !unknown.isEmpty else { return }
        let details = unknown.map { "'\($0.path)' (expected one of: \($0.validKeys.joined(separator: ", ")))" }
        throw ConfigError.unknownKeys(path: path, details: details)
    }

    /// Renders a `DecodingError` from TOML config decoding as a human-readable
    /// message naming the offending key path, instead of dumping the raw Swift
    /// error (which can mention internal types like `OffsetDateTime`).
    /// - Parameter error: The decoding error.
    /// - Returns: A one-line human-readable description.
    static func describe(_ error: DecodingError) -> String {
        switch error {
        case .typeMismatch(let type, let context), .valueNotFound(let type, let context):
            let expected = friendlyName(of: type).map { " (expected \($0))" } ?? ""
            return "key '\(keyPath(context.codingPath))' has the wrong type or value\(expected)"
        case .keyNotFound(let key, let context):
            return "required key '\(keyPath(context.codingPath + [key]))' is missing"
        case .dataCorrupted(let context):
            if context.codingPath.isEmpty {
                return "could not parse TOML: \(context.debugDescription)"
            }
            return "key '\(keyPath(context.codingPath))' is invalid: \(context.debugDescription)"
        @unknown default:
            return String(describing: error)
        }
    }

    /// Joins a coding path into a dotted, snake_cased key path with `[N]` array
    /// indices, matching how the key appears in the TOML file.
    private static func keyPath(_ codingPath: [any CodingKey]) -> String {
        var rendered = ""
        for key in codingPath {
            if let index = key.intValue {
                rendered += "[\(index)]"
            } else {
                rendered += rendered.isEmpty ? snakeCased(key.stringValue) : ".\(snakeCased(key.stringValue))"
            }
        }
        return rendered.isEmpty ? "(document root)" : rendered
    }

    /// Converts a camelCase coding key back to the snake_case the file uses
    /// (the decoder converts `test_gap` to `testGap` before erroring).
    private static func snakeCased(_ key: String) -> String {
        var result = ""
        for character in key {
            if character.isUppercase {
                result.append("_")
                result.append(Character(character.lowercased()))
            } else {
                result.append(character)
            }
        }
        return result
    }

    /// A user-facing name for an expected decoded type, or `nil` for types the
    /// user should never see (the decoder can report internal placeholder types
    /// like `OffsetDateTime` after exhausting its coercion attempts).
    private static func friendlyName(of type: Any.Type) -> String? {
        switch type {
        case is Double.Type, is Float.Type: return "a number"
        case is Int.Type, is Int64.Type: return "an integer"
        case is String.Type: return "a string"
        case is Bool.Type: return "a boolean (true/false)"
        default: return nil
        }
    }

    /// Resolves which config to use, honoring `--config` / `--no-config` and
    /// auto-discovering `.augur.toml` at the repository root otherwise.
    /// - Parameters:
    ///   - explicitPath: A `--config <path>` override, if any.
    ///   - disabled: Whether `--no-config` was passed.
    ///   - repoPath: The repository root (the `-C` path).
    /// - Returns: A resolved engine, its exclusion globs, and the path that was
    ///   loaded (for messaging), or `nil` when no config applies.
    static func load(
        explicitPath: String?,
        disabled: Bool,
        repoPath: String
    ) throws -> (engine: RiskEngine, excludes: [String], source: String)? {
        if disabled { return nil }

        let fileManager = FileManager.default
        let path: String
        if let explicitPath {
            path = explicitPath
        } else {
            let discovered = (repoPath as NSString).appendingPathComponent(defaultFilename)
            guard fileManager.fileExists(atPath: discovered) else { return nil }
            path = discovered
        }

        guard let data = fileManager.contents(atPath: path) else {
            throw ConfigError.unreadable(path)
        }
        let text = String(decoding: data, as: UTF8.self)
        try checkUnknownKeys(text: text, path: path)
        let config: AugurConfig
        do {
            config = try decode(text: text)
        } catch let error as DecodingError {
            throw ConfigError.invalid(path: path, underlying: describe(error))
        } catch {
            throw ConfigError.invalid(path: path, underlying: String(describing: error))
        }
        warnIfWeightsDoNotSumToOne(config)
        return (config.makeEngine(), config.resolvedExcludes(), path)
    }

    /// Tolerance (absolute) for the documented invariant that signal weights sum
    /// to ~1.0.
    static let weightSumTolerance = 0.01

    /// Warns (without failing) when a custom `[weights]` block does not sum to
    /// ~1.0, keeping the documented blend invariant honest. Only fires when the
    /// block is present, so default configs stay silent.
    static func warnIfWeightsDoNotSumToOne(_ config: AugurConfig) {
        guard config.weights != nil else { return }
        let resolved = config.resolvedWeights()
        let total = resolved.sensitivity + resolved.testGap + resolved.churn + resolved.coupling
            + resolved.diffShape + resolved.ownership + resolved.incident + resolved.codeowners
        guard abs(total - 1.0) > weightSumTolerance else { return }
        Diagnostics.warn(
            "[weights] sum to \(String(format: "%.4f", total)), not 1.0; scores are blended as-is and may not be comparable to defaults."
        )
    }
}

// MARK: - Errors

enum ConfigError: Error, LocalizedError, Sendable {
    case unreadable(String)
    case invalid(path: String, underlying: String)
    case unknownKeys(path: String, details: [String])

    var errorDescription: String? {
        switch self {
        case .unreadable(let path):
            return "Could not read config at \(path)"
        case .invalid(let path, let underlying):
            return "Invalid config at \(path): \(underlying)"
        case .unknownKeys(let path, let details):
            let noun = details.count == 1 ? "key" : "keys"
            return "Invalid config at \(path): unknown \(noun) \(details.joined(separator: "; ")). "
                + "Unknown keys are rejected so a typo cannot silently disable a rule; "
                + "rename or remove them (or pass --no-config to ignore the file)."
        }
    }
}
