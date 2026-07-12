# Requirements — Command-Line Interface

## Functional

### REQ-command-line-interface-001

The implementation SHALL satisfy this requirement.

Acceptance Criteria

- Expose `check` (default), `gate`, `calibrate`, and `explain` subcommands over the `AugurKit` engine.
### REQ-command-line-interface-002

The implementation SHALL satisfy this requirement.

Acceptance Criteria

- Resolve a diff scope from `--range`, `--staged`, or the working tree, and reject conflicting scope flags.
### REQ-command-line-interface-003

The implementation SHALL satisfy this requirement.

Acceptance Criteria

- Render `check` output as human text, `--json`, `--markdown`, or `--sarif` / `--sarif-out` (mutually exclusive).
### REQ-command-line-interface-004

The implementation SHALL satisfy this requirement.

Acceptance Criteria

- `gate` exits non-zero iff the verdict meets or exceeds `--threshold` (proceed / review / block).
### REQ-command-line-interface-005

The implementation SHALL satisfy this requirement.

Acceptance Criteria

- Load `.augur.toml` (auto-discovered or `--config`), resolving thresholds, weights, sensitivity rules, and exclusion globs; `--no-config` uses built-in defaults.
### REQ-command-line-interface-006

The implementation SHALL satisfy this requirement.

Acceptance Criteria

- Reject unknown config keys (fail-closed) so a typo cannot silently disable a rule.
### REQ-command-line-interface-007

The implementation SHALL satisfy this requirement.

Acceptance Criteria

- Discover coverage reports (LCOV / Cobertura / JaCoCo / Go) and CODEOWNERS files at the repo root, honoring `--no-coverage` / `--no-codeowners`.
### REQ-command-line-interface-008

The implementation SHALL satisfy this requirement.

Acceptance Criteria

- Cache the calibration model to `.augur/cache.json` (`calibrate`) and reuse it under `check --cached`, warning when stale.
### REQ-command-line-interface-009

The implementation SHALL satisfy this requirement.

Acceptance Criteria

- Combine configured and `--exclude` globs into a `PathFilter`; report excluded paths.

## Non-functional

### REQ-command-line-interface-010

The implementation SHALL satisfy this requirement.

Acceptance Criteria

- Confine all non-determinism (clock, TTY, filesystem, `git`) and third-party dependencies to this target; keep `AugurKit` pure and dependency-free.
### REQ-command-line-interface-011

The implementation SHALL satisfy this requirement.

Acceptance Criteria

- stdout carries only the requested output; every note and warning goes to stderr.
### REQ-command-line-interface-012

The implementation SHALL satisfy this requirement.

Acceptance Criteria

- Absent or empty `.augur.toml` is behavior-identical to built-in defaults (additive configuration).
### REQ-command-line-interface-013

The implementation SHALL satisfy this requirement.

Acceptance Criteria

- Human-readable errors — a bad config names the offending key path, never a raw Swift error.
### REQ-command-line-interface-014

The implementation SHALL satisfy this requirement.

Acceptance Criteria

- Honor `NO_COLOR` and TTY detection for `--color auto`.
