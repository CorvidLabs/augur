@preconcurrency import Foundation
import ArgumentParser
import AugurKit

@main
struct AugurCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "augur",
        abstract: "Graded trust for changes — how risky is this diff, and should a human look?",
        discussion: """
        augur scores a diff with deterministic signals (churn, co-change coupling, \
        test gaps, sensitive paths, ownership, and the repo's own revert history) and \
        returns a verdict: proceed, review, or block. No API key or LLM required.
        """,
        version: "0.1.0",
        subcommands: [Check.self, Gate.self, Explain.self],
        defaultSubcommand: Check.self
    )
}

// MARK: - Shared options

struct ScopeOptions: ParsableArguments {
    @Option(name: .long, help: "A git range to assess, e.g. 'main..HEAD'.")
    var range: String?

    @Flag(name: .long, help: "Assess staged changes (git diff --cached).")
    var staged = false

    @Option(name: [.long, .customShort("C")], help: "Path to the repository.")
    var path: String = "."

    func resolvedScope() -> DiffScope {
        if let range { return .range(range) }
        if staged { return .staged }
        return .workingTree
    }

    func makeAugur() throws -> (Augur, DiffScope) {
        let repo = GitRepository(path: path)
        try repo.validate()
        return (Augur(probe: repo), resolvedScope())
    }
}

// MARK: - check

struct Check: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Assess a change and print a risk verdict.")

    @OptionGroup var scope: ScopeOptions

    @Flag(name: .long, help: "Emit machine-readable JSON.")
    var json = false

    @Flag(name: [.long, .customShort("v")], help: "Show every contributing signal.")
    var verbose = false

    func run() async throws {
        let (augur, diffScope) = try scope.makeAugur()
        do {
            let assessment = try augur.assess(scope: diffScope)
            if json {
                print(try assessment.jsonString())
            } else {
                print(Reporter.render(assessment, verbose: verbose))
            }
        } catch AugurError.noChanges {
            if json { print("{\"verdict\":\"proceed\",\"riskScore\":0,\"files\":[]}") }
            else { print("augur · no changes to assess") }
        }
    }
}

// MARK: - gate

struct Gate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Exit non-zero if the verdict meets or exceeds a threshold (for CI / agent loops)."
    )

    @OptionGroup var scope: ScopeOptions

    @Option(name: .long, help: "Threshold verdict: proceed, review, or block.")
    var threshold: String = "review"

    @Flag(name: .long, help: "Emit machine-readable JSON.")
    var json = false

    func run() async throws {
        guard let limit = Verdict(rawValue: threshold) else {
            throw ValidationError("threshold must be one of: proceed, review, block")
        }
        let (augur, diffScope) = try scope.makeAugur()
        let assessment: Assessment
        do {
            assessment = try augur.assess(scope: diffScope)
        } catch AugurError.noChanges {
            return  // nothing to gate
        }
        if json { print(try assessment.jsonString()) }
        else { print("augur gate · \(assessment.verdict.rawValue) (risk \(Int(assessment.riskScore.rounded())))") }
        if assessment.verdict >= limit {
            throw ExitCode(1)
        }
    }
}

// MARK: - explain (optional AI, delegated to fledge)

struct Explain: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Optional: ask fledge's AI to explain why a change is risky (no key needed if fledge has one)."
    )

    @OptionGroup var scope: ScopeOptions

    func run() async throws {
        let (augur, diffScope) = try scope.makeAugur()
        let assessment = try augur.assess(scope: diffScope)
        let summary = Reporter.render(assessment, verbose: true)

        // augur stays AI-free; explanation is delegated to fledge's configured provider.
        let prompt = """
        Explain this change-risk assessment in plain language and suggest what a \
        reviewer should focus on. Be concise.

        \(summary)
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["fledge", "ask", prompt, "--non-interactive"]
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                print("\n(augur: `fledge ask` unavailable — assessment above is fully usable without AI.)")
            }
        } catch {
            print(summary)
            print("\n(augur: install fledge for optional AI explanations; the assessment above needs none.)")
        }
    }
}
