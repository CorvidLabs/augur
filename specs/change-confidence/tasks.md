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

## Done (v7)

- [x] CODEOWNERS parser in `AugurKit` (`CodeOwners.swift`, Foundation-only, reusing `GlobPattern`): comments/blanks, `<pattern> @owner...`, gitignore-like pattern → glob translation, `owners(for:)` with last-match-wins; `standardLocations` (`.github/CODEOWNERS`, `CODEOWNERS`, `docs/CODEOWNERS`).
- [x] New `codeowners` signal in `RiskEngine.assessFile`: neutral (`0`) with no CODEOWNERS, `0.6` for an unowned file, `0` (owner listed) when owned. `Weights` gains `codeowners` (`0.08`); the seven prior weights scaled by `0.92` so the blend still sums to `1.0`. Optional `codeOwners:` threaded through both `Augur.assess(...)` overloads and `RiskEngine.assess(...)` (default `nil`).
- [x] CLI: `check`/`gate` auto-discover CODEOWNERS at the standard locations; `--no-codeowners` disables; owner surfaced in the signal detail (human + JSON); `.augur.toml [weights] codeowners` parseable.
- [x] Spec → v7 (Public API, invariants, behavioral examples, change log); `fledge spec check` 0 errors.
- [x] Substantially expanded tests: CODEOWNERS semantics, engine codeowners signal + weights-sum + determinism (byte-identical JSON), parser/diff robustness (malformed/empty LCOV/Cobertura/JaCoCo/Go, binary/rename/unicode/space numstat, unified=0 edge cases, log parsing), pathological globs (63 → 114 tests).

## Done (v9)

- [x] Native markdown report (`MarkdownReporter.swift`, Foundation-only, `Sendable`): `render(_:) -> String` emitting deterministic GitHub-flavored markdown: verdict heading with a per-verdict emoji (✅/⚠️/⛔, no em-dashes), a confidence/calibration line, a riskiest-first `| File | Risk | Verdict | Top signal |` table capped at `maxRows` (25) with an "and N more" overflow line, and a trailing `<!-- augur-report -->` marker for sticky PR comments. Table cells escape `\`/`|`/newlines.
- [x] CLI: `check --markdown` prints the report to stdout, mutually exclusive with `--json` and `--sarif` (validated with a clear error).
- [x] CI (`ci.yml`): meaningful PR risk range (`origin/<base>..HEAD` on `pull_request`, `HEAD~1..HEAD` on push) applied to the commit-status step and the new steps; `pull-requests: write` added; a PR-only step writes the markdown to `$GITHUB_STEP_SUMMARY` and posts/updates a sticky PR comment found via the `<!-- augur-report -->` marker (best-effort).
- [x] Tests: heading per verdict, riskiest-first table order, top-signal selection, marker presence, row-cap overflow, pipe escaping, determinism, and a golden markdown snapshot (136 → 151 tests).
- [x] Spec → v9 (Public API, behavioral example, change log); `fledge spec check` 0 errors. Docs: `docs/cli.md`, `docs/ci-integration.md`, README usage.

## Next

- [ ] Phase 2: `attest` — signed provenance records keyed to commit SHAs (a projection of `Assessment`).
- [ ] Linux/Windows CI matrix and static binaries.
- [ ] Cross-repo packaging of the `augur gate` action (install a published binary instead of building from the action's own checkout).
