@preconcurrency import Foundation

/// A path-based sensitivity rule: changes under matching paths carry inherent risk.
///
/// Language-agnostic and configurable. The defaults target the categories that
/// most often turn a routine change into an incident.
public struct SensitivityRule: Sendable, Equatable {
    public let label: String
    public let risk: Double
    public let fragments: [String]

    public init(label: String, risk: Double, fragments: [String]) {
        self.label = label
        self.risk = risk
        self.fragments = fragments
    }

    func matches(_ path: String) -> Bool {
        let lower = path.lowercased()
        return fragments.contains { lower.contains($0) }
    }
}

public enum SensitivityRuleset {
    /// Built-in defaults, ordered by descending severity.
    public static let `default`: [SensitivityRule] = [
        SensitivityRule(label: "secrets", risk: 1.0, fragments: [".env", "secret", "credential", ".pem", "id_rsa", ".p12"]),
        SensitivityRule(label: "auth", risk: 0.9, fragments: ["auth", "login", "session", "token", "oauth", "password", "permission", "rbac"]),
        SensitivityRule(label: "crypto", risk: 0.85, fragments: ["crypto", "encrypt", "decrypt", "signing", "hmac", "keychain"]),
        SensitivityRule(label: "payments", risk: 0.85, fragments: ["payment", "billing", "charge", "invoice", "stripe", "checkout"]),
        SensitivityRule(label: "migration", risk: 0.8, fragments: ["migration", "migrate", "schema", "/sql/"]),
        SensitivityRule(label: "infra", risk: 0.7, fragments: ["dockerfile", "terraform", ".tf", "k8s", "kubernetes", "helm", "ansible"]),
        SensitivityRule(label: "ci", risk: 0.6, fragments: [".github/workflows", ".gitlab-ci", "jenkinsfile", "circleci", "fledge.toml"]),
        SensitivityRule(label: "dependencies", risk: 0.55, fragments: ["package.json", "package-lock", "yarn.lock", "cargo.toml", "cargo.lock", "go.mod", "go.sum", "package.resolved", "requirements.txt", "pyproject.toml", "gemfile"]),
    ]

    /// The highest-severity rule that matches the path, if any.
    public static func match(_ path: String, rules: [SensitivityRule] = `default`) -> SensitivityRule? {
        rules.filter { $0.matches(path) }.max(by: { $0.risk < $1.risk })
    }
}

/// Test-file detection, language-agnostic via common naming conventions.
public enum TestHeuristics {
    private static let markers = [
        "test", "spec", "__tests__", ".test.", ".spec.", "_test.", "tests/", "/test/",
    ]

    public static func isTestFile(_ path: String) -> Bool {
        let lower = path.lowercased()
        return markers.contains { lower.contains($0) }
    }
}
