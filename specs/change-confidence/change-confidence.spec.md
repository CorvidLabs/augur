---
module: change-confidence
version: 3
status: draft
files:
  - Sources/AugurKit/Models.swift
  - Sources/AugurKit/Git.swift
  - Sources/AugurKit/History.swift
  - Sources/AugurKit/Sensitivity.swift
  - Sources/AugurKit/RiskEngine.swift
  - Sources/AugurKit/Augur.swift
  - Sources/AugurKit/Reporter.swift
  - Sources/AugurKit/Coverage.swift
db_tables: []
depends_on: []
---

# Change Confidence

## Purpose

Produce a deterministic, language-agnostic risk/confidence verdict for a set of changes
so that **humans** can triage where to spend review attention and **agents** can decide
whether to proceed or ask for human review. The core requires no API key and no LLM:
every signal is derived from `git` history and the filesystem. Optional AI explanations
are delegated to `fledge` and are purely additive.

The scoring has two layers:

1. A transparent **heuristic prior** (documented weights) that always applies.
2. A **history calibration** that scales the incident signal by how much the repository's
   own revert/hotfix record backs it, reported via `Calibration` so consumers know whether
   a score is "prior-only" or "history-backed".

## Public API

### Entry Point

| Export | Description |
|--------|-------------|
| `Augur.init(probe:engine:historyLimit:)` | Construct the facade over a `RepositoryProbe`. |
| `Augur.assess(scope:now:coverage:)` | Probe the repository and return an `Assessment` for a `DiffScope`; an optional `CoverageReport` sharpens the test-gap signal per changed line. |
| `Assessment.jsonString()` | Render the assessment as stable, sorted-key JSON for agents. |
| `Assessment.jsonData()` | Same as `jsonString()` but returns `Data`. |
| `Reporter.render(_:verbose:)` | Render an `Assessment` as human-readable terminal text. |

### Engine

| Export | Description |
|--------|-------------|
| `RiskEngine.init(weights:rules:thresholds:)` | Construct the engine with prior weights, sensitivity rules, and verdict thresholds. |
| `RiskEngine.assess(scope:changedFiles:history:now:coverage:)` | Pure scoring over an explicit change surface and history, with an optional `CoverageReport`. |
| `RiskEngine.Weights` | Documented prior weights for each signal (sum to 1.0); `Codable`. |
| `RiskEngine.calibrationConfidence(totalCommits:incidentCommits:)` | Static calibration-confidence function (0...1). |

### Repository Access

| Export | Description |
|--------|-------------|
| `RepositoryProbe` | Protocol providing `changedFiles(in:)`, `recentCommits(limit:)`, and `headSHA()`. |
| `GitRepository` | `RepositoryProbe` backed by the `git` CLI; `validate()` confirms a work tree; `headSHA()` reports `HEAD`. |
| `HistorySnapshot.init(commits:)` | Derives churn, recency, ownership, coupling, and incidents from commits. |
| `HistorySnapshot.init(cache:)` | Rebuilds an equivalent snapshot from a `CalibrationCache` without re-walking `git log`. |
| `HistorySnapshot.makeCache(head:)` | Produces a serializable `CalibrationCache` pinned to a `HEAD` SHA. |
| `Augur.assess(scope:history:now:coverage:)` | Assess using a pre-built snapshot (e.g. from a cache), skipping the log walk; optional `CoverageReport`. |
| `RepositoryProbe.addedLines(in:)` | Added (new-revision) line numbers per file in a scope; default `[:]`. `GitRepository` parses `git diff --unified=0`. |
| `Augur.calibrate()` | Walk history once and return a `CalibrationCache` pinned to the current `HEAD`. |
| `Augur.currentHead()` | The current `HEAD` SHA of the underlying repository. |

### Sensitivity

| Export | Description |
|--------|-------------|
| `SensitivityRule` | A path-fragment rule carrying an inherent risk weight. |
| `SensitivityRuleset.default` | Built-in rules: secrets, auth, crypto, payments, migration, infra, ci, dependencies. |
| `SensitivityRuleset.match(_:rules:)` | Highest-severity matching rule for a path, if any. |
| `TestHeuristics.isTestFile(_:)` | Language-agnostic test-file detection. |

### Coverage

| Export | Description |
|--------|-------------|
| `CoverageReport` | Parsed line coverage keyed by file; `query(path:changedLines:)` and `matchFile(diffPath:)`. |
| `CoverageReport.FileCoverage` | Per-file instrumented and covered line-number sets. |
| `CoverageQuery` | Result of a query: `covered`, `instrumented`, `fileMatched`, and `coveredFraction` (`nil` when nothing instrumented). |
| `CoverageParser.load(path:)` | Loads and parses an LCOV (`.info`) or Cobertura (`.xml`) file from disk. |
| `CoverageParser.parse(contents:path:)` | Parses report text, auto-detecting the format. |
| `CoverageParser.parseLCOV(_:)` / `parseCobertura(_:)` | Format-specific parsers (Foundation-only; Cobertura via `XMLParser`). |
| `CoverageParser.detectFormat(path:contents:)` | Detects `.lcov` / `.cobertura` by extension then content sniffing. |
| `CoverageParser.Format` / `CoverageParser.ParseError` | The format enum and parse-failure errors. |

### Types & Enums

| Type | Description |
|------|-------------|
| `DiffScope` | `range(String)`, `staged`, or `workingTree` — the unit assessed. |
| `ChangedFile` | A touched file with added/deleted line counts, a binary flag, and `addedLines` (new-revision line numbers; empty when unknown). |
| `Commit` | A historical commit: hash, author email, timestamp, subject, files. |
| `Signal` | One deterministic risk contribution (`risk` 0...1, `weight`, `detail`). |
| `Verdict` | `proceed`, `review`, or `block`; `Comparable`; `from(riskScore:)` and `from(riskScore:thresholds:)`. |
| `Thresholds` | Configurable `review` / `block` cutoffs (0...100); `.default` is `35` / `65`; `review` is clamped `<= block`. |
| `FileAssessment` | Per-file `riskScore` (0...100), `confidence`, `verdict`, `verdict(thresholds:)`, and `signals`. |
| `Calibration` | `confidence` (0...1), `totalCommits`, `incidentCommits`, and a `band`. |
| `CalibrationCache` | `Codable` projection of a `HistorySnapshot` pinned to a `head` SHA; `confidence`, `band`, `jsonData()`, `decoded(from:)`. |
| `Assessment` | Overall `riskScore`, `verdict`, `calibration`, `thresholds`, and per-file results. |
| `AugurError` | `notARepository`, `git`, `noChanges`. |

## Invariants

- `Signal.risk`, `FileAssessment.riskScore / 100`, and `Calibration.confidence` are clamped to `0...1` (scores to `0...100`).
- `FileAssessment.confidence == 100 - riskScore`; likewise for `Assessment`.
- `Verdict.from(riskScore:)` uses the default thresholds: `< 35 → proceed`, `< 65 → review`, otherwise `block`. `Verdict.from(riskScore:thresholds:)` applies configurable cutoffs (`>= block → block`, `>= review → review`, else `proceed`), and with `Thresholds.default` is identical to the convenience overload.
- `Thresholds` clamps `review` to be no greater than `block`, and both into `0...100`.
- A single file scoring `>= 80` forces the overall verdict to at least `block`.
- Thresholds change only the score→verdict mapping, never the `riskScore`; identical inputs under different thresholds yield identical scores.
- A `CalibrationCache` is a lossless projection of the snapshot facts the engine queries: a snapshot rebuilt via `HistorySnapshot(cache:)` produces an `Assessment` identical to one from the original commits. `topPartner` ties are broken by partner path so the projection is deterministic.
- The heuristic prior always contributes; the incident signal is multiplied by `Calibration.confidence`, so on a history-free repository the incident contribution is `0`.
- `RiskEngine.Weights` sum to `1.0`; per-file score is the weight-normalized blend of its signals.
- Assessment is deterministic: identical `(changedFiles, history, now, coverage)` yield identical output. Coverage parsing and matching use no `Date`/randomness.
- Coverage precedence in the test-gap signal: when a `CoverageReport` is supplied and the file is a non-test, non-binary code file with instrumented changed lines, `risk = 1 - covered/instrumented`; a code file entirely absent from the report is `0.7` ("not in coverage report"); when coverage cannot refine the file (no added lines known, or no changed line instrumented) the existing heuristic applies. With no coverage supplied, the heuristic test-gap behavior is unchanged.
- `CoverageQuery` counts only *instrumented* changed lines: a changed line the tool never instrumented contributes to neither `covered` nor `instrumented`, and `coveredFraction` is `nil` when `instrumented == 0`.
- Coverage path matching is by normalized longest-suffix at component boundaries; exact (normalized) matches win, ties break by shorter then lexicographically-smaller reported path. Diff/coverage prefix differences are tolerated; identical suffixes across distinct files are ambiguous (documented limitation).
- `Augur.assess` is pure with respect to an injected `now`, enabling reproducible tests.

## Behavioral Examples

- A 3-line docs edit, no sensitive paths, tests untouched → `proceed` (risk `< 35`).
- A 160-line edit to `src/auth/token.swift` with no test in the changeset → at least `review`; the `sensitivity` and `test-gap` signals are non-zero.
- The same source change *with* a sibling test file in the changeset scores strictly lower than without it.
- A file repeatedly implicated in `Revert "..."` commits, in a repo with deep history, raises the `incident` signal and reports `calibration.confidence > 0.5`.
- `calibrationConfidence(totalCommits: 10, incidentCommits: 0) < 0.25`; `calibrationConfidence(totalCommits: 400, incidentCommits: 40) > 0.6`.
- A change that scores `proceed` under the default thresholds becomes `block` under `Thresholds(review: 1, block: 2)` while keeping the same `riskScore`.
- A custom `SensitivityRule` merged onto `SensitivityRuleset.default` makes a previously-unflagged path (e.g. `pkg/internal/api.swift`) match, raising its `sensitivity` signal and overall score, while built-in categories still match.
- Encoding a `HistorySnapshot` to a `CalibrationCache`, JSON round-tripping it, and rebuilding via `HistorySnapshot(cache:)` yields an `Assessment` equal to the live one.
- A code file whose changed lines (e.g. `10,11,12`) are all covered scores `test-gap` risk `0` ("3/3 changed lines covered (100%)"); the same file with those lines uncovered scores risk `1` ("0/3 ..."), and its overall `riskScore` is strictly higher than the covered case.
- A changed code file absent from the supplied coverage report scores `test-gap` risk `0.7` ("not in coverage report").
- Parsing LCOV `SF:`/`DA:` records and Cobertura `<class filename><lines><line number hits>` yields, per file, the instrumented and covered line-number sets; `query(path:changedLines:)` restricts counts to instrumented changed lines.
- A coverage path `/build/checkout/Sources/App/Service.swift` matches the diff path `Sources/App/Service.swift` by longest suffix; a path sharing no trailing component does not match.

## Error Cases

- `AugurError.notARepository(path)` — `GitRepository.validate()` finds no git work tree at `path`.
- `AugurError.git(command:status:)` — an underlying `git` invocation exits non-zero.
- `AugurError.noChanges` — the requested scope contains no changed files; the CLI treats this as a clean `proceed`.

## Dependencies

- `git` available on `PATH` (the only runtime requirement of the core).
- `swift-argument-parser` (CLI target only; `AugurKit` has no external dependencies).
- `TOMLDecoder` (CLI target only) to parse `.augur.toml`; `AugurKit` stays dependency-free.
- `fledge` (optional, `augur explain` only) for AI explanations.

## Change Log

- v3: Per-line coverage ingestion (`Coverage.swift`). New `CoverageReport` / `CoverageReport.FileCoverage` / `CoverageQuery` types and a Foundation-only `CoverageParser` (LCOV + Cobertura XML via `XMLParser`, with format auto-detection and `load(path:)`). `ChangedFile` gains `addedLines` (default empty, back-compatible). `RepositoryProbe` gains `addedLines(in:)` (default `[:]`); `GitRepository` parses `git diff --unified=0` hunk headers to populate it. Optional `coverage:` parameter threaded through `RiskEngine.assess(...)` and both `Augur.assess(...)` overloads (default `nil`); when supplied, the test-gap signal becomes `1 - covered/instrumented` over a file's instrumented changed lines (absent file → `0.7`), otherwise the original heuristic is unchanged. CLI adds `--coverage <path>` and `--no-coverage` to `check`/`gate`, with auto-detection of `lcov.info` / `coverage.xml` at the repo root. A composite `action.yml` ("augur gate") builds augur from its own checkout and gates on self-hosted macOS. `AugurKit` remains free of third-party dependencies.
- v2: Configurable verdict thresholds via `Thresholds` (engine + `Verdict.from(riskScore:thresholds:)`), threaded through `RiskEngine.init(weights:rules:thresholds:)` and surfaced on `Assessment.thresholds`. `Weights` is now `Codable`. Added `CalibrationCache` (a `Codable` projection of `HistorySnapshot`) with `HistorySnapshot.init(cache:)` / `makeCache(head:)`, `Augur.calibrate()` / `assess(scope:history:now:)` / `currentHead()`, and `RepositoryProbe.headSHA()`. `topPartner` now breaks ties deterministically by partner path. CLI adds `.augur.toml` config (parsed in the CLI layer only), the `calibrate` command, `check --cached`, and `--config` / `--no-config`. `AugurKit` remains free of third-party dependencies.
- v1: Initial change-confidence engine — deterministic signals (sensitivity, test-gap, churn, coupling, diff-shape, ownership, incident), two-layer prior + history calibration, JSON and human reporters, `check`/`gate`/`explain` CLI.
