# Tasks — Command-Line Interface

## Done (v1)

- [x] `AugurCommand` root with `check` (default), `gate`, `calibrate`, and `explain` subcommands.
- [x] Shared option groups: `ScopeOptions`, `ConfigOptions`, `ExcludeOptions`, `CoverageOptions`, `CodeOwnersOptions`, `ColorOptions`.
- [x] `check` output as human, `--json`, `--markdown`, and `--sarif` / `--sarif-out` (mutually exclusive, validated).
- [x] `gate` exit-code behavior against a `--threshold` verdict, validated at parse time.
- [x] `.augur.toml` loading via `ConfigLoader`: discovery, snake_case decode, engine construction, exclusion globs.
- [x] Unknown-key rejection via `TOMLShape` + `ConfigSchema` (fail-closed, with valid-sibling hints and array indices).
- [x] Human-readable `DecodingError` rendering that names the key path; `[weights]` sum warning.
- [x] Coverage report resolution (explicit + auto-detect) and CODEOWNERS discovery.
- [x] `.augur/cache.json` store (`CacheStore`) with `check --cached` reuse and staleness warning.
- [x] `Diagnostics` stderr channel so stdout stays pipe-clean.
- [x] `explain` delegating to `fledge ask` with a graceful fallback when unavailable.

## Not planned

- [ ] Interactive prompts — the CLI stays non-interactive and scriptable for agent loops.
