# Tasks — Change Confidence

## Done (v1)

- [x] `RepositoryProbe` protocol + `GitRepository` (numstat + single-pass log parsing).
- [x] `HistorySnapshot` deriving churn, recency, ownership, coupling, incidents.
- [x] Signals: sensitivity, test-gap, churn, coupling, diff-shape, ownership, incident.
- [x] Two-layer scoring: heuristic prior + history calibration with reported confidence.
- [x] `Verdict` thresholds + single-hot-file escalation.
- [x] JSON and human reporters.
- [x] CLI: `check`, `gate`, `explain` (AI delegated to fledge).
- [x] Unit tests over the engine with an in-memory probe.

## Done (v2)

- [x] `augur calibrate` to cache the history model and report backing volume (`.augur/cache.json`, pinned to `HEAD`).
- [x] `augur check --cached` reuses the cache with a staleness warning when `HEAD` moved.
- [x] Configurable sensitivity rules, signal weights, and verdict thresholds via `.augur.toml` (parsed in the CLI layer; `AugurKit` stays dependency-free).
- [x] `Thresholds` type + `Verdict.from(riskScore:thresholds:)`; `CalibrationCache` round-trippable projection of `HistorySnapshot`.
- [x] `--config` / `--no-config` flags; custom rules merge with defaults (or replace via `[sensitivity] replace_defaults`).
- [x] Tests for custom thresholds, merged rules, default-threshold equivalence, and cache round-trip.
- [x] Examples (`examples/*.sh`) and self-hosted macOS CI (`.github/workflows/ci.yml`).

## Done (v3)

- [x] Per-line coverage ingestion (lcov/cobertura) to sharpen the test-gap signal per line.
- [x] `CoverageReport` / `CoverageParser` (Foundation-only) + `ChangedFile.addedLines` from `git diff --unified=0`.
- [x] `--coverage <path>` / `--no-coverage` on `check`/`gate`, with auto-detection of `lcov.info` / `coverage.xml`.
- [x] Composite `action.yml` ("augur gate") for self-hosted macOS; meaningful dogfood step in CI.
- [x] Tests: LCOV + Cobertura parsing, suffix path-matching, unified=0 parsing, and covered-vs-uncovered scoring.

## Done (v4)

- [x] SARIF 2.1.0 output (`Sarif.swift`, Foundation-only `Codable`): `SarifReport(from:)` projecting an `Assessment` into one `run`, one `result` per file under the single `augur/change-risk` rule.
- [x] Verdict→level mapping (`block → error`, `review → warning`, `proceed → note`); `region.startLine` from the file's first added line; `riskScore`/`confidence`/`verdict` in `result.properties`.
- [x] CLI `--sarif` / `--sarif-out <path>` on `check` (mutually exclusive with `--json`); `Augur.addedLines(in:)` passthrough for regions.
- [x] Tests: level mapping, result count, region from `addedLines`, deterministic JSON round-trip.
- [x] Example `examples/07-sarif.sh` + reusable `examples/workflows/sarif.yml` (with `upload-sarif` and the GHAS-on-private caveat).

## Done (v5)

- [x] JaCoCo XML ingestion (`parseJaCoCo`, Foundation `XMLParser`): `<line nr mi ci>` under `<package><sourcefile>`; instrumented when a `line` exists, covered when `ci > 0`; path = `package@name`/`sourcefile@name`.
- [x] Go coverprofile ingestion (`parseGoProfile`, text): `mode:` header then `path:start.col,end.col numStmts count` blocks; lines `start...end` instrumented, covered when any covering block has `count > 0`.
- [x] `CoverageParser.Format` gains `jacoco` / `go`; `detectFormat` recognizes both (markers / `mode:` / extensions) with LCOV + Cobertura unchanged. `--coverage` accepts all four; auto-detect adds `jacoco.xml` / `cover.out` / `coverage.out`.
- [x] Tests: JaCoCo + Go parsing (counts, path assembly, multi/overlapping blocks), `detectFormat`, and covered-vs-uncovered scoring under each new format (46 tests total).
- [x] Example `examples/08-coverage-formats.sh` demonstrating JaCoCo and Go coverprofile lowering risk on covered changed lines.

## Done (v6)

- [x] Glob matcher in `AugurKit` (`Glob.swift`, Foundation-only): `GlobPattern` (`*` / `**` / `?`, whole-path anchored, compiled to `NSRegularExpression`) and `PathFilter` (`[GlobPattern]` wrapper with `excludes(_:)`).
- [x] `Augur.assess(...)` gains an optional `filter:`; matching files are dropped before scoring and recorded in `Assessment.excludedPaths` (sorted, `excludedCount`). Excluding all files throws `noChanges`.
- [x] `.augur.toml [exclude] paths = [...]` (CLI layer); `check`/`gate` gain repeatable `--exclude <glob>` and `--no-exclude`; reporter prints `excluded: N files`, JSON includes `excludedPaths`.
- [x] Tests: glob `*`/`**`/`?`, anchoring, directory globs, non-matches; assessment exclusion + exclude-all-yields-no-changes + nil-filter behavior-preserving (63 tests total).
- [x] Example `examples/09-exclude.sh` (excluding a vendored/generated path changes the assessment).

## Next

- [ ] Phase 2: `attest` — signed provenance records keyed to commit SHAs (a projection of `Assessment`).
- [ ] Linux/Windows CI matrix and static binaries.
- [ ] Cross-repo packaging of the `augur gate` action (install a published binary instead of building from the action's own checkout).
