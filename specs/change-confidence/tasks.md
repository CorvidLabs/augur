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

## Next

- [ ] `augur calibrate` to cache the history model and report backing volume.
- [ ] Configurable sensitivity rules via `.augur.toml`.
- [ ] Phase 2: `attest` — signed provenance records keyed to commit SHAs (a projection of `Assessment`).
- [ ] Linux/Windows CI matrix and static binaries.
- [ ] Coverage-report ingestion (lcov/cobertura) to sharpen the test-gap signal per line.
