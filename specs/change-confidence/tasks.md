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

## Next

- [ ] Phase 2: `attest` — signed provenance records keyed to commit SHAs (a projection of `Assessment`).
- [ ] Linux/Windows CI matrix and static binaries.
- [ ] Coverage-report ingestion (lcov/cobertura) to sharpen the test-gap signal per line.
