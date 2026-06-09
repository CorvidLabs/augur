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
        let config: AugurConfig
        do {
            config = try decode(text: text)
        } catch {
            throw ConfigError.invalid(path: path, underlying: String(describing: error))
        }
        return (config.makeEngine(), config.resolvedExcludes(), path)
    }
}

// MARK: - Errors

enum ConfigError: Error, LocalizedError, Sendable {
    case unreadable(String)
    case invalid(path: String, underlying: String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let path):
            return "Could not read config at \(path)"
        case .invalid(let path, let underlying):
            return "Invalid config at \(path): \(underlying)"
        }
    }
}
