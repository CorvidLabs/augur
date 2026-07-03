---
module: command-line-interface
version: 1
status: draft
files:
  - Sources/augur/AugurCommand.swift
  - Sources/augur/Config.swift
  - Sources/augur/CacheStore.swift
db_tables: []
depends_on:
  - change-confidence
---

# Command-Line Interface

## Purpose

The `augur` executable is the **IO and adapter layer** around the pure
`AugurKit` engine. It parses arguments and an optional `.augur.toml`, discovers
coverage and CODEOWNERS files, resolves a configured `RiskEngine`, runs an
assessment over a chosen diff scope, and renders the verdict as human text,
JSON, GitHub-flavored markdown, or SARIF.

Its job is to keep the boundary clean: **every source of non-determinism and
every third-party dependency lives here**, never in `AugurKit`. TOML decoding
(`TOMLDecoder`), the filesystem, `git`, the wall clock, and TTY detection are
all confined to this target, so the engine stays deterministic and free of
third-party dependencies (the repository's golden rules).

## Public API

### Command tree

`AugurCommand` is the `@main` root (`AsyncParsableCommand`); `check` is the
default subcommand.

| Command | Role |
|---------|------|
| `check` | Assess a diff and print a risk verdict. Output is human (default), `--json`, `--markdown`, or `--sarif` / `--sarif-out <file>` (mutually exclusive); `--verbose` shows every signal; `--cached` reuses `.augur/cache.json`. |
| `gate` | Exit non-zero when the verdict meets or exceeds `--threshold` (proceed / review / block), for CI and agent loops. |
| `calibrate` | Walk history once and cache the calibration model to `.augur/cache.json` for `check --cached`. |
| `explain` | Optional AI explanation, delegated to `fledge ask` as a subprocess; augur itself stays AI-free. |

### Shared option groups (`ParsableArguments`)

| Group | Options | Resolves to |
|-------|---------|-------------|
| `ScopeOptions` | `--range`, `--staged`, `-C/--path` | A `DiffScope` and an `Augur` over a validated `GitRepository`. `--range` and `--staged` are mutually exclusive. |
| `ConfigOptions` | `--config`, `--no-config` | A `RiskEngine` and the config's exclusion globs, via `ConfigLoader.load`. |
| `ExcludeOptions` | `--exclude <glob>` (repeatable), `--no-exclude` | A `PathFilter` combining configured and ad-hoc globs (or `nil`). |
| `CoverageOptions` | `--coverage <path>`, `--no-coverage` | A `CoverageReport` from an explicit path or an auto-detected report at the repo root (`lcov.info`, `coverage.xml`, `jacoco.xml`, `cover.out`, `coverage.out`). |
| `CodeOwnersOptions` | `--no-codeowners` | A parsed `CodeOwners` discovered at `.github/CODEOWNERS`, `CODEOWNERS`, or `docs/CODEOWNERS`. |
| `ColorOptions` | `--color auto\|always\|never` | Whether to emit ANSI color; `auto` is on only for a TTY with `NO_COLOR` unset. |

### Configuration (`Config.swift`)

- `AugurConfig` (`Decodable, Sendable`): the decoded `.augur.toml` — `[thresholds]`,
  `[weights]`, `[[rules]]`, `[sensitivity]`, `[exclude]`. All sections optional.
  Resolves to `Thresholds`, `RiskEngine.Weights`, `[SensitivityRule]`, exclusion
  globs, and a `RiskEngine` via `makeEngine()`.
- `ConfigLoader`: discovers (`.augur.toml`), reads, and decodes config
  (snake_case keys); rejects unknown keys; renders `DecodingError`s as
  human-readable messages; warns when a `[weights]` block does not sum to ~1.0.
- `TOMLShape` / `ConfigSchema`: a structural mirror of the document and the known
  schema, used to detect unknown keys (`TOMLDecoder` silently ignores them, so a
  typo'd rule would otherwise fail open).
- `ConfigError` (`Error, LocalizedError, Sendable`): `unreadable`, `invalid`,
  `unknownKeys`.

### Cache and diagnostics (`CacheStore.swift`)

- `CacheStore`: reads and writes the repo-local, git-ignored calibration cache at
  `.augur/cache.json`; `load` returns `nil` when absent or unreadable.
- `Diagnostics`: `note` / `warn` write one-line `augur:` messages to **stderr**,
  so status never pollutes the stdout stream a caller may pipe.

## Invariants

1. All non-determinism (clock, TTY, filesystem, `git`) and all third-party
   dependencies (`TOMLDecoder`, `ArgumentParser`) live in this target; `AugurKit`
   stays pure and dependency-free.
2. **stdout carries only the requested output** (the report, JSON, markdown, or
   SARIF). Every note and warning goes to stderr through `Diagnostics`.
3. An absent or empty `.augur.toml` is equivalent to the built-in defaults:
   configuration is strictly additive and behavior-preserving when omitted.
4. Unknown configuration keys are **rejected** (fail-closed), never silently
   ignored, so a typo cannot disable a rule.
5. Conflicting selections are validated, not silently resolved: `--range` vs
   `--staged`, and `--json` vs `--markdown` vs `--sarif`.
6. `gate` exits non-zero **iff** the verdict is greater than or equal to the
   threshold; `check` never sets a non-zero exit from the verdict alone.
7. An explicit `--coverage` path that fails to parse is a hard error; a stray
   unparseable auto-detected report only loses auto-detection (warn and fall
   back to the heuristic test-gap signal).

## Behavioral Examples

```
Given a repository with unstaged changes
When `augur check` runs with no flags
Then it assesses the working tree, prints the human report with the verdict
     (proceed / review / block), and exits 0 regardless of the verdict.
```

```
Given `augur gate --threshold block` and a change whose verdict is review
When it runs
Then it prints the one-line gate summary and exits 0 (review < block);
     the same change under `--threshold review` would exit 1.
```

```
Given an .augur.toml containing a typo'd key such as [[sensitivity.rules]]
When any command loads config
Then ConfigLoader throws ConfigError.unknownKeys naming the bad path and the
     valid keys at that level, the command exits non-zero, and the message
     points the user at --no-config; the typo never silently fails open.
```

```
Given `augur calibrate -C <repo>`
When it runs
Then it walks history once, writes .augur/cache.json, and prints the cached
     path, HEAD, commit/incident volume, and calibration band to stdout.
```

```
Given `augur check --json --exclude 'vendor/**'`
When it runs
Then it prints a single JSON object with the assessment and excludedPaths, and
     a one-line "exclude: N pattern(s) active" note goes to stderr, not stdout.
```

## Error Cases

| Condition | Result |
|-----------|--------|
| `--range` and `--staged` both set | `ValidationError` ("mutually exclusive; pass exactly one scope"). |
| More than one of `--json` / `--markdown` / `--sarif` | `ValidationError` from `check.validate`. |
| `gate --threshold` not in {proceed, review, block} | `ValidationError` naming the valid values. |
| `.augur.toml` present but unreadable | `ConfigError.unreadable`. |
| `.augur.toml` fails to decode | `ConfigError.invalid` with a human-readable key path (never a raw Swift error). |
| `.augur.toml` has unknown keys | `ConfigError.unknownKeys` listing each bad path and its valid siblings. |
| Explicit `--coverage <path>` unparseable | Hard error from `CoverageParser.load`. |
| Auto-detected coverage file unparseable | `Diagnostics.warn`, then fall back to the heuristic test-gap (no failure). |
| Path is not a git repository | Thrown from `GitRepository.validate()`. |

## Dependencies

- **`AugurKit`** (`change-confidence`): the pure engine and all domain types —
  `Augur`, `RiskEngine` (`Weights`, `Thresholds`), `SensitivityRule` /
  `SensitivityRuleset`, `CoverageReport` / `CoverageParser`, `CodeOwners`,
  `PathFilter`, `GitRepository`, `DiffScope`, `Assessment`, `Reporter` /
  `MarkdownReporter`, `SarifReport`, `CalibrationCache`, `HistorySnapshot`,
  `Verdict`, `AugurError`.
- **`swift-argument-parser`** — the command tree and option parsing.
- **`TOMLDecoder`** — `.augur.toml` decoding (CLI target only).
- **Foundation** — `FileManager`, `Process` (for `fledge ask`), `isatty`.

## Change Log

| Version | Date | Changes |
|---------|------|---------|
| 1 | 2026-07-03 | Initial spec: documents the augur CLI (command tree, shared option groups, `.augur.toml` loading with unknown-key rejection, the `.augur/cache.json` store, and stderr diagnostics) as the IO/adapter boundary around the pure `AugurKit` engine. |
