# Requirements — Change Confidence

## Functional

- R1: Assess a `DiffScope` (`range`, `staged`, `workingTree`) and return per-file and overall risk.
- R2: Emit a `Verdict` of `proceed`, `review`, or `block`.
- R3: Derive every core signal from `git` + filesystem only — no API key, no LLM.
- R4: Report calibration provenance (`prior-only`, `weak`, `history-backed`) on every assessment.
- R5: Provide stable, sorted-key JSON output for agent consumption.
- R6: Provide a `gate` mode that exits non-zero when the verdict meets a threshold.
- R7: Keep `AugurKit` free of third-party dependencies; the CLI may depend on `swift-argument-parser`.
- R8: Version the assessment JSON contract and emit the same complete shape for empty and non-empty diffs.

## Non-functional

- N1: Deterministic — identical `(changedFiles, history, now)` produce identical output.
- N2: Fast cold start suitable for pre-commit hooks and agent inner loops.
- N3: Cross-platform target (macOS first; Linux/Windows via Foundation `Process`).
- N4: Engine fully testable without invoking `git` (via the `RepositoryProbe` protocol).
