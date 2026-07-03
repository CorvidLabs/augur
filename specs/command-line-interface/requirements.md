# Requirements — Command-Line Interface

## Functional

- R1: Expose `check` (default), `gate`, `calibrate`, and `explain` subcommands over the `AugurKit` engine.
- R2: Resolve a diff scope from `--range`, `--staged`, or the working tree, and reject conflicting scope flags.
- R3: Render `check` output as human text, `--json`, `--markdown`, or `--sarif` / `--sarif-out` (mutually exclusive).
- R4: `gate` exits non-zero iff the verdict meets or exceeds `--threshold` (proceed / review / block).
- R5: Load `.augur.toml` (auto-discovered or `--config`), resolving thresholds, weights, sensitivity rules, and exclusion globs; `--no-config` uses built-in defaults.
- R6: Reject unknown config keys (fail-closed) so a typo cannot silently disable a rule.
- R7: Discover coverage reports (LCOV / Cobertura / JaCoCo / Go) and CODEOWNERS files at the repo root, honoring `--no-coverage` / `--no-codeowners`.
- R8: Cache the calibration model to `.augur/cache.json` (`calibrate`) and reuse it under `check --cached`, warning when stale.
- R9: Combine configured and `--exclude` globs into a `PathFilter`; report excluded paths.

## Non-functional

- N1: Confine all non-determinism (clock, TTY, filesystem, `git`) and third-party dependencies to this target; keep `AugurKit` pure and dependency-free.
- N2: stdout carries only the requested output; every note and warning goes to stderr.
- N3: Absent or empty `.augur.toml` is behavior-identical to built-in defaults (additive configuration).
- N4: Human-readable errors — a bad config names the offending key path, never a raw Swift error.
- N5: Honor `NO_COLOR` and TTY detection for `--color auto`.
