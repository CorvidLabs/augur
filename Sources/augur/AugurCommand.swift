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
        version: "0.2.0",
        subcommands: [Check.self, Gate.self, Calibrate.self, Explain.self],
        defaultSubcommand: Check.self
    )
}

// MARK: - Shared options

struct ConfigOptions: ParsableArguments {
    @Option(name: .long, help: "Path to an .augur.toml config (default: auto-discover at the repo root).")
    var config: String?

    @Flag(name: .long, help: "Ignore any .augur.toml and use built-in defaults.")
    var noConfig = false

    /// Resolves the engine from config, printing a one-line note to stderr when a
    /// config file is applied so the effect is visible.
    func resolvedEngine(repoPath: String) throws -> RiskEngine {
        guard let resolved = try ConfigLoader.load(explicitPath: config, disabled: noConfig, repoPath: repoPath) else {
            return RiskEngine()
        }
        Diagnostics.note("config: loaded \(resolved.source)")
        return resolved.engine
    }
}

struct CoverageOptions: ParsableArguments {
    @Option(name: .long, help: "Path to a coverage report (LCOV .info, Cobertura/JaCoCo .xml, or Go .out coverprofile) to sharpen the test-gap signal per line.")
    var coverage: String?

    @Flag(name: .long, help: "Disable coverage auto-detection at the repo root.")
    var noCoverage = false

    /// Standard report filenames auto-detected at the repository root, in
    /// precedence order (the first that exists wins, logged to stderr).
    static let autoDetectNames = ["lcov.info", "coverage.xml", "jacoco.xml", "cover.out", "coverage.out"]

    /// Resolves a coverage report from `--coverage`, else by auto-detecting a
    /// standard filename at the repo root (unless `--no-coverage`). Prints a
    /// one-line note to stderr when a report is loaded. Returns `nil` when none
    /// applies, leaving the heuristic test-gap behavior unchanged.
    func resolved(repoPath: String) throws -> CoverageReport? {
        if let coverage {
            let report = try CoverageParser.load(path: coverage)
            Diagnostics.note("coverage: loaded \(coverage)")
            return report
        }
        guard !noCoverage else { return nil }
        let fileManager = FileManager.default
        for name in Self.autoDetectNames {
            let candidate = (repoPath as NSString).appendingPathComponent(name)
            guard fileManager.fileExists(atPath: candidate) else { continue }
            let report = try CoverageParser.load(path: candidate)
            Diagnostics.note("coverage: auto-detected \(candidate)")
            return report
        }
        return nil
    }
}

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

    func makeAugur(config: ConfigOptions) throws -> (Augur, DiffScope) {
        let repo = GitRepository(path: path)
        try repo.validate()
        let engine = try config.resolvedEngine(repoPath: path)
        return (Augur(probe: repo, engine: engine), resolvedScope())
    }
}

// MARK: - check

struct Check: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Assess a change and print a risk verdict.")

    @OptionGroup var scope: ScopeOptions
    @OptionGroup var configOptions: ConfigOptions
    @OptionGroup var coverageOptions: CoverageOptions

    @Flag(name: .long, help: "Emit machine-readable JSON.")
    var json = false

    @Flag(name: .long, help: "Emit SARIF 2.1.0 (for GitHub code scanning). Mutually exclusive with --json.")
    var sarif = false

    @Option(name: .long, help: "Write SARIF to this file instead of stdout (implies --sarif).")
    var sarifOut: String?

    @Flag(name: [.long, .customShort("v")], help: "Show every contributing signal.")
    var verbose = false

    @Flag(name: .long, help: "Reuse .augur/cache.json instead of re-walking git history.")
    var cached = false

    /// Whether SARIF output was requested (explicitly, or implied by `--sarif-out`).
    private var wantsSarif: Bool { sarif || sarifOut != nil }

    func validate() throws {
        if json && wantsSarif {
            throw ValidationError("--json and --sarif are mutually exclusive.")
        }
    }

    func run() async throws {
        let (augur, diffScope) = try scope.makeAugur(config: configOptions)
        let coverage = try coverageOptions.resolved(repoPath: scope.path)
        do {
            let assessment = try assess(augur, scope: diffScope, coverage: coverage)
            if wantsSarif {
                try emitSarif(assessment, augur: augur, scope: diffScope)
            } else if json {
                print(try assessment.jsonString())
            } else {
                print(Reporter.render(assessment, verbose: verbose))
            }
        } catch AugurError.noChanges {
            if wantsSarif {
                let empty = Assessment(
                    scope: diffScope.label,
                    riskScore: 0,
                    verdict: .proceed,
                    calibration: Calibration(confidence: 0, totalCommits: 0, incidentCommits: 0),
                    files: []
                )
                try emitSarif(empty, augur: augur, scope: diffScope)
            } else if json {
                print("{\"verdict\":\"proceed\",\"riskScore\":0,\"files\":[]}")
            } else {
                print("augur · no changes to assess")
            }
        }
    }

    /// Builds a SARIF report from the assessment and writes it to the chosen sink.
    private func emitSarif(_ assessment: Assessment, augur: Augur, scope diffScope: DiffScope) throws {
        let added = (try? augur.addedLines(in: diffScope)) ?? [:]
        let report = SarifReport(
            from: assessment,
            toolVersion: AugurCommand.configuration.version,
            addedLinesByPath: added
        )
        let payload = try report.jsonString()
        if let sarifOut {
            try payload.write(toFile: sarifOut, atomically: true, encoding: .utf8)
            Diagnostics.note("sarif: wrote \(sarifOut)")
        } else {
            print(payload)
        }
    }

    private func assess(_ augur: Augur, scope diffScope: DiffScope, coverage: CoverageReport?) throws -> Assessment {
        guard cached else { return try augur.assess(scope: diffScope, coverage: coverage) }
        guard let cache = CacheStore.load(repoPath: scope.path) else {
            Diagnostics.note("no cache found at \(CacheStore.path(repoPath: scope.path)); computing live. Run `augur calibrate` first.")
            return try augur.assess(scope: diffScope, coverage: coverage)
        }
        if let head = try? augur.currentHead(), !head.isEmpty, !cache.head.isEmpty, head != cache.head {
            Diagnostics.note("cache is stale (calibrated at \(cache.head.prefix(8)), HEAD is \(head.prefix(8))); results may be outdated.")
        }
        return try augur.assess(scope: diffScope, history: HistorySnapshot(cache: cache), coverage: coverage)
    }
}

// MARK: - gate

struct Gate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Exit non-zero if the verdict meets or exceeds a threshold (for CI / agent loops)."
    )

    @OptionGroup var scope: ScopeOptions
    @OptionGroup var configOptions: ConfigOptions
    @OptionGroup var coverageOptions: CoverageOptions

    @Option(name: .long, help: "Threshold verdict: proceed, review, or block.")
    var threshold: String = "review"

    @Flag(name: .long, help: "Emit machine-readable JSON.")
    var json = false

    func run() async throws {
        guard let limit = Verdict(rawValue: threshold) else {
            throw ValidationError("threshold must be one of: proceed, review, block")
        }
        let (augur, diffScope) = try scope.makeAugur(config: configOptions)
        let coverage = try coverageOptions.resolved(repoPath: scope.path)
        let assessment: Assessment
        do {
            assessment = try augur.assess(scope: diffScope, coverage: coverage)
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

// MARK: - calibrate

struct Calibrate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Walk history once and cache the calibration model to .augur/cache.json for `check --cached`."
    )

    @Option(name: [.long, .customShort("C")], help: "Path to the repository.")
    var path: String = "."

    @Flag(name: .long, help: "Emit machine-readable JSON.")
    var json = false

    func run() async throws {
        let repo = GitRepository(path: path)
        try repo.validate()
        let augur = Augur(probe: repo)
        let cache = try augur.calibrate()
        try CacheStore.save(cache, repoPath: path)

        if json {
            print(String(decoding: try cache.jsonData(), as: UTF8.self))
            return
        }
        let head = cache.head.isEmpty ? "(unknown)" : String(cache.head.prefix(8))
        print("augur calibrate · cached \(CacheStore.path(repoPath: path))")
        print("  HEAD         \(head)")
        print("  volume       \(cache.totalCommits) commits, \(cache.incidentCommits) incidents")
        print("  calibration  \(cache.band) (confidence \(String(format: "%.2f", cache.confidence)))")
    }
}

// MARK: - explain (optional AI, delegated to fledge)

struct Explain: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Optional: ask fledge's AI to explain why a change is risky (no key needed if fledge has one)."
    )

    @OptionGroup var scope: ScopeOptions
    @OptionGroup var configOptions: ConfigOptions

    func run() async throws {
        let (augur, diffScope) = try scope.makeAugur(config: configOptions)
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
