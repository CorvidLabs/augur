# Requirements — Change Confidence

## Functional

### REQ-change-confidence-001

The implementation SHALL satisfy this requirement.

Acceptance Criteria

- Assess a `DiffScope` (`range`, `staged`, `workingTree`) and return per-file and overall risk.
### REQ-change-confidence-002

The implementation SHALL satisfy this requirement.

Acceptance Criteria

- Emit a `Verdict` of `proceed`, `review`, or `block`.
### REQ-change-confidence-003

The implementation SHALL satisfy this requirement.

Acceptance Criteria

- Derive every core signal from `git` + filesystem only — no API key, no LLM.
### REQ-change-confidence-004

The implementation SHALL satisfy this requirement.

Acceptance Criteria

- Report calibration provenance (`prior-only`, `weak`, `history-backed`) on every assessment.
### REQ-change-confidence-005

The implementation SHALL satisfy this requirement.

Acceptance Criteria

- Provide stable, sorted-key JSON output for agent consumption.
### REQ-change-confidence-006

The implementation SHALL satisfy this requirement.

Acceptance Criteria

- Provide a `gate` mode that exits non-zero when the verdict meets a threshold.
### REQ-change-confidence-007

The implementation SHALL satisfy this requirement.

Acceptance Criteria

- Keep `AugurKit` free of third-party dependencies; the CLI may depend on `swift-argument-parser`.
### REQ-change-confidence-008

The implementation SHALL satisfy this requirement.

Acceptance Criteria

- Version the assessment JSON contract and emit the same complete shape for empty and non-empty diffs.

## Non-functional

### REQ-change-confidence-009

The implementation SHALL satisfy this requirement.

Acceptance Criteria

- Deterministic — identical `(changedFiles, history, now)` produce identical output.
### REQ-change-confidence-010

The implementation SHALL satisfy this requirement.

Acceptance Criteria

- Fast cold start suitable for pre-commit hooks and agent inner loops.
### REQ-change-confidence-011

The implementation SHALL satisfy this requirement.

Acceptance Criteria

- Cross-platform target (macOS first; Linux/Windows via Foundation `Process`).
### REQ-change-confidence-012

The implementation SHALL satisfy this requirement.

Acceptance Criteria

- Engine fully testable without invoking `git` (via the `RepositoryProbe` protocol).
