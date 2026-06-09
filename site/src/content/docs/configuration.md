---
title: "Configuration"
description: "The full .augur.toml reference — thresholds, weights, rules, exclude — plus CLI overrides."
section: "Reference"
order: 4
---

`augur` runs with sensible built-in defaults and needs no configuration. To tune
it, drop an `.augur.toml` at the repository root. Every section is optional — an
empty or absent file is exactly equivalent to the defaults, so configuration is
strictly additive.

The file is parsed entirely in the CLI layer (via `TOMLDecoder`); `AugurKit`
never sees TOML. Keys use `snake_case` and map to the engine's camelCase fields.

## Full reference

```toml
# .augur.toml — every section is optional.

# ── Verdict cutoffs (0...100). score >= block -> block; >= review -> review; else proceed.
#    Defaults: review = 35, block = 65. review is clamped to be <= block.
[thresholds]
review = 35
block  = 65

# ── Signal weights for the heuristic prior. Only listed keys are overridden;
#    omitted keys keep their defaults. They need NOT sum to 1.0 — the engine
#    normalizes by the total weight — but keeping them ~1.0 keeps scores intuitive.
[weights]
sensitivity = 0.2024
test_gap    = 0.1656
churn       = 0.138
coupling    = 0.1196
diff_shape  = 0.1104
ownership   = 0.092
incident    = 0.092
codeowners  = 0.08

# ── Sensitivity rules. By default custom rules are MERGED onto the built-ins.
#    Set replace_defaults = true to use ONLY the custom rules below.
[sensitivity]
replace_defaults = false

# A changed path containing any fragment (case-insensitive substring) matches,
# carrying the given risk (0...1). Repeat the [[rules]] table for more.
[[rules]]
label     = "internal-api"
risk      = 0.7
fragments = ["internal/", "/unstable/"]

[[rules]]
label     = "feature-flags"
risk      = 0.5
fragments = ["featureflag", "flags.json"]

# ── Drop generated / vendored / lockfile paths from the assessment entirely.
#    Glob-matched (see docs/cli.md for glob syntax). Excluded files appear in
#    neither the scored set nor any signal.
[exclude]
paths = ["vendor/**", "**/*.generated.swift", "**/Package.resolved"]
```

## Section details

### `[thresholds]`

Maps the overall risk score to a verdict. `review` is clamped to be no greater
than `block`, and both are clamped into `0...100`. Changing thresholds never
changes the `riskScore` — only the score → verdict mapping.

### `[weights]`

Overrides the per-field prior weights. See [signals.md](signals.md) for what each
signal does. The engine blends signals as `Σ risk·weight / Σ weight`, so weights
are *relative*; they do not have to sum to `1.0`. Setting a weight to `0` removes
that signal's contribution.

| TOML key | Signal | Default |
|----------|--------|--------:|
| `sensitivity` | sensitivity | `0.2024` |
| `test_gap` | test-gap | `0.1656` |
| `churn` | churn | `0.138` |
| `coupling` | coupling | `0.1196` |
| `diff_shape` | diff-shape | `0.1104` |
| `ownership` | ownership (git history) | `0.092` |
| `incident` | incident | `0.092` |
| `codeowners` | codeowners | `0.08` |

### `[sensitivity]` + `[[rules]]`

Custom rules flag paths whose (lowercased) text contains any listed `fragment`.
By default they are appended to the built-in categories; set
`replace_defaults = true` to use only your rules. The highest-`risk` matching
rule wins for a given path.

### `[exclude]`

Glob patterns whose matching changed files are dropped *before* scoring (and
reported under `excludedPaths`). Useful for vendored trees, generated code, and
lockfiles. See the glob syntax in [cli.md](cli.md#glob-syntax).

## CODEOWNERS

The `codeowners` signal reads a separate, standard `CODEOWNERS` file (not
`.augur.toml`) auto-discovered at `.github/CODEOWNERS`, `CODEOWNERS`, or
`docs/CODEOWNERS`. You tune only its *weight* in `.augur.toml [weights] codeowners`;
the owner rules themselves live in `CODEOWNERS`. See
[signals.md](signals.md#codeowners).

## CLI overrides

| Flag | Effect |
|------|--------|
| `--config <path>` | Use an explicit `.augur.toml` instead of auto-discovery. |
| `--no-config` | Ignore any `.augur.toml`; use built-in defaults. |
| `--exclude <glob>` | Add an ad-hoc exclude glob (repeatable). Always applied. |
| `--no-exclude` | Ignore `[exclude]` from config (CLI `--exclude` still applies). |
| `--no-codeowners` | Disable CODEOWNERS discovery (the `codeowners` signal stays neutral). |
| `--no-coverage` | Disable coverage auto-detection. |

When a config or CODEOWNERS file is applied, `augur` prints a one-line note to
**stderr** so the effect is visible without polluting stdout/JSON.
