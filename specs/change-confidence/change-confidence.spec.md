---
module: change-confidence
version: 1
status: draft
files:
  - Sources/AugurKit/Models.swift
  - Sources/AugurKit/Git.swift
  - Sources/AugurKit/History.swift
  - Sources/AugurKit/Sensitivity.swift
  - Sources/AugurKit/RiskEngine.swift
  - Sources/AugurKit/Augur.swift
  - Sources/AugurKit/Reporter.swift
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
| `Augur.assess(scope:now:)` | Probe the repository and return an `Assessment` for a `DiffScope`. |
| `Assessment.jsonString()` | Render the assessment as stable, sorted-key JSON for agents. |
| `Assessment.jsonData()` | Same as `jsonString()` but returns `Data`. |
| `Reporter.render(_:verbose:)` | Render an `Assessment` as human-readable terminal text. |

### Engine

| Export | Description |
|--------|-------------|
| `RiskEngine.init(weights:rules:)` | Construct the engine with prior weights and sensitivity rules. |
| `RiskEngine.assess(scope:changedFiles:history:now:)` | Pure scoring over an explicit change surface and history. |
| `RiskEngine.Weights` | Documented prior weights for each signal (sum to 1.0). |
| `RiskEngine.calibrationConfidence(totalCommits:incidentCommits:)` | Static calibration-confidence function (0...1). |

### Repository Access

| Export | Description |
|--------|-------------|
| `RepositoryProbe` | Protocol providing `changedFiles(in:)` and `recentCommits(limit:)`. |
| `GitRepository` | `RepositoryProbe` backed by the `git` CLI; `validate()` confirms a work tree. |
| `HistorySnapshot.init(commits:)` | Derives churn, recency, ownership, coupling, and incidents from commits. |

### Sensitivity

| Export | Description |
|--------|-------------|
| `SensitivityRule` | A path-fragment rule carrying an inherent risk weight. |
| `SensitivityRuleset.default` | Built-in rules: secrets, auth, crypto, payments, migration, infra, ci, dependencies. |
| `SensitivityRuleset.match(_:rules:)` | Highest-severity matching rule for a path, if any. |
| `TestHeuristics.isTestFile(_:)` | Language-agnostic test-file detection. |

### Types & Enums

| Type | Description |
|------|-------------|
| `DiffScope` | `range(String)`, `staged`, or `workingTree` — the unit assessed. |
| `ChangedFile` | A touched file with added/deleted line counts and a binary flag. |
| `Commit` | A historical commit: hash, author email, timestamp, subject, files. |
| `Signal` | One deterministic risk contribution (`risk` 0...1, `weight`, `detail`). |
| `Verdict` | `proceed`, `review`, or `block`; `Comparable`; `from(riskScore:)`. |
| `FileAssessment` | Per-file `riskScore` (0...100), `confidence`, `verdict`, and `signals`. |
| `Calibration` | `confidence` (0...1), `totalCommits`, `incidentCommits`, and a `band`. |
| `Assessment` | Overall `riskScore`, `verdict`, `calibration`, and per-file results. |
| `AugurError` | `notARepository`, `git`, `noChanges`. |

## Invariants

- `Signal.risk`, `FileAssessment.riskScore / 100`, and `Calibration.confidence` are clamped to `0...1` (scores to `0...100`).
- `FileAssessment.confidence == 100 - riskScore`; likewise for `Assessment`.
- `Verdict.from(riskScore:)`: `< 35 → proceed`, `< 65 → review`, otherwise `block`.
- A single file scoring `>= 80` forces the overall verdict to at least `block`.
- The heuristic prior always contributes; the incident signal is multiplied by `Calibration.confidence`, so on a history-free repository the incident contribution is `0`.
- `RiskEngine.Weights` sum to `1.0`; per-file score is the weight-normalized blend of its signals.
- Assessment is deterministic: identical `(changedFiles, history, now)` yield identical output.
- `Augur.assess` is pure with respect to an injected `now`, enabling reproducible tests.

## Behavioral Examples

- A 3-line docs edit, no sensitive paths, tests untouched → `proceed` (risk `< 35`).
- A 160-line edit to `src/auth/token.swift` with no test in the changeset → at least `review`; the `sensitivity` and `test-gap` signals are non-zero.
- The same source change *with* a sibling test file in the changeset scores strictly lower than without it.
- A file repeatedly implicated in `Revert "..."` commits, in a repo with deep history, raises the `incident` signal and reports `calibration.confidence > 0.5`.
- `calibrationConfidence(totalCommits: 10, incidentCommits: 0) < 0.25`; `calibrationConfidence(totalCommits: 400, incidentCommits: 40) > 0.6`.

## Error Cases

- `AugurError.notARepository(path)` — `GitRepository.validate()` finds no git work tree at `path`.
- `AugurError.git(command:status:)` — an underlying `git` invocation exits non-zero.
- `AugurError.noChanges` — the requested scope contains no changed files; the CLI treats this as a clean `proceed`.

## Dependencies

- `git` available on `PATH` (the only runtime requirement of the core).
- `swift-argument-parser` (CLI target only; `AugurKit` has no external dependencies).
- `fledge` (optional, `augur explain` only) for AI explanations.

## Change Log

- v1: Initial change-confidence engine — deterministic signals (sensitivity, test-gap, churn, coupling, diff-shape, ownership, incident), two-layer prior + history calibration, JSON and human reporters, `check`/`gate`/`explain` CLI.
