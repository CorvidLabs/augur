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

## Durable Requirements

### REQ-change-confidence-001

The implementation SHALL satisfy the following criterion: Assess a `DiffScope` (`range`, `staged`, `workingTree`) and return per-file and overall risk.

Acceptance Criteria

- Assess a `DiffScope` (`range`, `staged`, `workingTree`) and return per-file and overall risk.

### REQ-change-confidence-002

The implementation SHALL satisfy the following criterion: Emit a `Verdict` of `proceed`, `review`, or `block`.

Acceptance Criteria

- Emit a `Verdict` of `proceed`, `review`, or `block`.

### REQ-change-confidence-003

The implementation SHALL satisfy the following criterion: Derive every core signal from `git` + filesystem only — no API key, no LLM.

Acceptance Criteria

- Derive every core signal from `git` + filesystem only — no API key, no LLM.

### REQ-change-confidence-004

The implementation SHALL satisfy the following criterion: Report calibration provenance (`prior-only`, `weak`, `history-backed`) on every assessment.

Acceptance Criteria

- Report calibration provenance (`prior-only`, `weak`, `history-backed`) on every assessment.

### REQ-change-confidence-005

The implementation SHALL satisfy the following criterion: Provide stable, sorted-key JSON output for agent consumption.

Acceptance Criteria

- Provide stable, sorted-key JSON output for agent consumption.

### REQ-change-confidence-006

The implementation SHALL satisfy the following criterion: Provide a `gate` mode that exits non-zero when the verdict meets a threshold.

Acceptance Criteria

- Provide a `gate` mode that exits non-zero when the verdict meets a threshold.

### REQ-change-confidence-007

The implementation SHALL satisfy the following criterion: Keep `AugurKit` free of third-party dependencies; the CLI may depend on `swift-argument-parser`.

Acceptance Criteria

- Keep `AugurKit` free of third-party dependencies; the CLI may depend on `swift-argument-parser`.

### REQ-change-confidence-008

The implementation SHALL satisfy the following criterion: Version the assessment JSON contract and emit the same complete shape for empty and non-empty diffs.

Acceptance Criteria

- Version the assessment JSON contract and emit the same complete shape for empty and non-empty diffs.

### REQ-change-confidence-009

The implementation SHALL satisfy the following criterion: Deterministic — identical `(changedFiles, history, now)` produce identical output.

Acceptance Criteria

- Deterministic — identical `(changedFiles, history, now)` produce identical output.

### REQ-change-confidence-010

The implementation SHALL satisfy the following criterion: Fast cold start suitable for pre-commit hooks and agent inner loops.

Acceptance Criteria

- Fast cold start suitable for pre-commit hooks and agent inner loops.

### REQ-change-confidence-011

The implementation SHALL satisfy the following criterion: Cross-platform target (macOS first; Linux/Windows via Foundation `Process`).

Acceptance Criteria

- Cross-platform target (macOS first; Linux/Windows via Foundation `Process`).

### REQ-change-confidence-012

The implementation SHALL satisfy the following criterion: Engine fully testable without invoking `git` (via the `RepositoryProbe` protocol).

Acceptance Criteria

- Engine fully testable without invoking `git` (via the `RepositoryProbe` protocol).
