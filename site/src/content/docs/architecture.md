---
title: "Architecture"
description: "AugurKit vs the CLI, the signal pipeline, two-layer scoring, and the zero-dependency invariant."
section: "Reference"
order: 5
---

`augur` is a deterministic change-risk engine: it reads a git diff and emits a
verdict (`proceed`, `review`, or `block`) from structural signals only. No API
key, no LLM in the core.

## Two targets

| Target | Role | Dependencies |
|--------|------|--------------|
| **`AugurKit`** (library) | The pure engine: probes, signals, scoring, calibration, coverage parsing, glob/CODEOWNERS matching, SARIF projection. | **Foundation only**, zero third-party deps. |
| **`augur`** (CLI) | Argument parsing, config loading, file discovery, output formatting, optional AI delegation. | `swift-argument-parser`, `TOMLDecoder` (CLI layer only). |

The split is deliberate and enforced:

- **`AugurKit` stays AI-free and dependency-free.** Never add a hosted-LLM, local
  model, or third-party package to it. Optional AI lives only in `augur explain`,
  which shells out to `fledge`.
- **Config (`.augur.toml`) is parsed entirely in the CLI.** The CLI decodes the
  file with `TOMLDecoder`, then constructs `RiskEngine(weights:rules:thresholds:)`
  and injects it into the pure engine. The engine never sees TOML.
- **Scoring is deterministic.** No `Date()` or randomness inside the engine; `now`
  is injected at the CLI boundary so tests are reproducible and assessments are
  byte-identical for identical inputs.

## The signal pipeline

```
git repo ──probe──▶ ChangedFile[] + Commit[]
                         │
              HistorySnapshot (churn, recency, ownership, coupling, incidents)
                         │
   optional: CoverageReport, PathFilter, CodeOwners
                         │
                  RiskEngine.assess
                         │
            per-file Signal[] ──weighted blend──▶ FileAssessment.riskScore
                         │
                  aggregate (max + mean + breadth)
                         │
              Assessment { riskScore, verdict, calibration, files, ... }
```

1. A `RepositoryProbe` (the `GitRepository` implementation, or an in-memory
   fixture in tests) supplies the **change surface** (`ChangedFile[]`) and
   **recent commits** (`Commit[]`).
2. `HistorySnapshot` derives query-friendly facts from the commits once: churn,
   recency, distinct authors, co-change partners, and incident-prone files.
3. `RiskEngine.assessFile` computes a list of `Signal`s per file (each a `risk`
   in `0...1`, a `weight`, and a human-readable `detail`).
4. The per-file score is the **weight-normalized blend** of its signals
   (`Σ risk·weight / Σ weight × 100`).
5. The overall score aggregates the files: `0.65 × max + 0.35 × mean + breadth`,
   where `breadth` adds a small penalty for touching many files. A single file
   scoring `≥ 80` forces the overall verdict to at least `block`.

See [signals.md](signals.md) for every signal and its weight.

## Two-layer scoring + calibration

Scoring has two layers:

1. **A transparent heuristic prior** with documented weights (see
   `RiskEngine.Weights`). This *always* applies, even on a brand-new repo with no
   history.
2. **A history calibration** that scales the `incident` signal by how much the
   repository's own revert/hotfix record backs it. On a history-free repo the
   incident contribution is `0`; as `augur` watches a repo accumulate commits and
   incidents, the calibration confidence grows.

Every `Assessment` reports a `Calibration` (`confidence`, `totalCommits`,
`incidentCommits`, and a `band`: `prior-only` → `weak` → `history-backed`) so a
consumer knows whether a score is "guessing" or "grounded".

The engine's primary output is risk. `Assessment.confidence` and
`FileAssessment.confidence` are convenience inverses (`100 - riskScore`) used by
human reports; they are not an independent model signal. `Calibration.confidence`
is the separate history-backing factor used only for the incident signal.

```
calibrationConfidence = min(1, commits/300) × (0.4 + 0.6 × min(1, incidents/25))
```

`augur calibrate` walks history once and caches a `CalibrationCache` (a lossless
projection of the snapshot facts the engine queries) to `.augur/cache.json`,
pinned to `HEAD`. A later `augur check --cached` rebuilds an equivalent snapshot
without re-walking `git log`, and warns when `HEAD` has moved.

## The zero-dependency invariant

`AugurKit` is Foundation-only by design. This is what makes augur trivially
embeddable, fast to build, and free of supply-chain surface in the part that
decides whether your change is safe. Concretely:

- **Coverage parsing** (LCOV / Cobertura / JaCoCo / Go) uses `XMLParser` and line
  parsing. See [coverage.md](coverage.md).
- **Glob matching** (`GlobPattern`) lowers globs to `NSRegularExpression`.
- **CODEOWNERS** (`CodeOwners`) reuses `GlobPattern` for path matching.
- **SARIF** output is a Foundation `Codable` model.

If a feature seems to need a dependency in `AugurKit`, it belongs in the CLI
layer instead (as TOML parsing does).
