---
title: "CLI reference"
description: "Every augur command and flag (check, gate, calibrate, explain) with examples, glob syntax, exit codes, and the JSON shape."
section: "Reference"
order: 3
---

```
augur <command> [options]
```

Commands: [`check`](#check) (default), [`gate`](#gate), [`calibrate`](#calibrate),
[`explain`](#explain). All commands require `git` on `PATH`. `augur` runs on macOS and Linux.

## Scope (shared by `check`, `gate`, `explain`)

`augur` is range-first. Pick one scope; the default is the working tree.

| Flag | Scope |
|------|-------|
| *(none)* | Working tree vs `HEAD` (staged + unstaged). |
| `--range <a..b>` | An explicit git range, e.g. `main..HEAD`. |
| `--staged` | Staged changes only (`git diff --cached`); ideal for pre-commit. |
| `-C, --path <dir>` | Path to the repository (default `.`). |

## check

Assess a change and print a risk verdict.

```sh
augur check                          # working-tree changes
augur check --range main..HEAD       # a range
augur check --staged                 # staged changes
augur check -v                       # show every contributing signal
augur check --json                   # machine-readable, sorted-key JSON
augur check --sarif                  # SARIF 2.1.0 for GitHub code scanning
augur check --sarif-out augur.sarif  # write SARIF to a file (implies --sarif)
augur check --cached                 # reuse .augur/cache.json (run `calibrate` first)
augur check --coverage lcov.info     # sharpen test-gap with coverage
augur check --exclude 'vendor/**'    # drop paths from the assessment (repeatable)
```

| Flag | Effect |
|------|--------|
| `-v, --verbose` | Show every contributing signal per file (not just the top one). |
| `--json` | Emit stable, sorted-key JSON. Mutually exclusive with `--sarif`. |
| `--sarif` | Emit SARIF 2.1.0. See [ci-integration.md](ci-integration.md). |
| `--sarif-out <path>` | Write SARIF to a file (implies `--sarif`). |
| `--cached` | Reuse the calibration cache instead of re-walking `git log`. |
| `--coverage <path>` | Coverage report to sharpen test-gap. See [coverage.md](coverage.md). |
| `--no-coverage` | Disable coverage auto-detection. |
| `--exclude <glob>` | Exclude matching paths (repeatable). See [glob syntax](#glob-syntax). |
| `--no-exclude` | Ignore `[exclude]` from config (CLI `--exclude` still applies). |
| `--no-codeowners` | Disable CODEOWNERS discovery (the `codeowners` signal stays neutral). |
| `--config <path>` | Use an explicit `.augur.toml`. |
| `--no-config` | Ignore any `.augur.toml`. |
| `--color <mode>` | `auto` (default), `always`, or `never`. See [Color output](#color-output). |

`check` always exits `0` (it reports; it does not gate). Use `gate` for CI.

### Color output

The human-readable report is **colored** by meaning: the verdict and per-file
markers are tinted <span style="color:var(--proceed)">green&nbsp;(proceed)</span> /
<span style="color:var(--review)">amber&nbsp;(review)</span> /
<span style="color:var(--block)">red&nbsp;(block)</span>, the
`█`/`░` risk meter is tinted by the same scale, file paths are
<span style="color:var(--term-cyan)">cyan</span>, and secondary detail is dimmed.

`--color` controls the human-readable `check` report:

| Mode | Behavior |
|------|----------|
| `auto` *(default)* | Color **only** when stdout is an interactive TTY. |
| `always` | Force color even when piped or redirected. |
| `never` | Never emit ANSI codes. |

In `auto`, `augur` also honors the [`NO_COLOR`](https://no-color.org) convention:
if `NO_COLOR` is set in the environment, color is disabled. `--json` and
`--sarif` output is **always** plain regardless of `--color`, so machine-readable
streams never carry escape codes.

## gate

Assess, then exit **non-zero** when the verdict meets or exceeds a threshold.
For CI pipelines and agent loops.

```sh
augur gate --threshold review        # exit 1 if verdict >= review
augur gate --threshold block --staged
augur gate --json
```

| Flag | Effect |
|------|--------|
| `--threshold <verdict>` | `proceed`, `review`, or `block` (default `review`). |
| `--json` | Emit JSON (else a one-line summary). |

`gate` also accepts every scope, coverage, exclude, codeowners, and config flag
that `check` does.

**Exit codes:**

| Code | Meaning |
|-----:|---------|
| `0` | Verdict below the threshold (or no changes to assess). |
| `1` | Verdict met or exceeded the threshold. |
| `2` | Usage / validation error (e.g. an invalid `--threshold`). |

## calibrate

Walk history once and cache the calibration model to `.augur/cache.json`, pinned
to `HEAD`, so `check --cached` can skip the `git log` walk.

```sh
augur calibrate
augur calibrate --json
```

| Flag | Effect |
|------|--------|
| `-C, --path <dir>` | Path to the repository. |
| `--json` | Emit the cache as JSON. |

Output reports the cached `HEAD`, the commit/incident volume, and the calibration
band (`prior-only` / `weak` / `history-backed`).

## explain

Optional AI explanation of an assessment, delegated to `fledge ask`. `augur`
itself stays AI-free; this is purely additive and needs no key of its own if
`fledge` is configured.

```sh
augur explain
augur explain --range main..HEAD
```

If `fledge` is unavailable, the plain assessment is printed and `augur` notes
that no AI is required to use it.

## Glob syntax

Used by `--exclude` / `[exclude]` and (after gitignore-style translation)
CODEOWNERS. Patterns are **anchored to the whole path**:

| Token | Matches |
|-------|---------|
| `*` | Any run of characters **except** `/` (within one path segment). |
| `**` | Any run of characters **including** `/` (and zero or more segments). |
| `?` | Exactly one character. |
| other | Literal (regex metacharacters are escaped). |

Examples: `vendor/**` matches `vendor`, `vendor/a`, and `vendor/a/b/c.swift` but
not `src/vendor/x`. `src/*.swift` matches `src/x.swift` but not `src/sub/x.swift`.
`**/*.generated.swift` matches at any depth. Paths are normalized (leading `./`,
duplicate/trailing slashes) before matching.

## JSON shape

`--json` emits a stable, sorted-key object. Top level:

```jsonc
{
  "schemaVersion": 1,
  "scope": "working-tree",
  "riskScore": 19.18,
  "verdict": "proceed",
  "calibration": { "band": "...", "confidence": 0.0, "totalCommits": 1, "incidentCommits": 0 },
  "thresholds": { "review": 35, "block": 65 },
  "excludedPaths": [],
  "files": [
    {
      "path": "lib/helper.swift",
      "riskScore": 19.18,
      "signals": [
        { "name": "codeowners", "risk": 0.6, "weight": 0.08, "detail": "no CODEOWNERS owner" }
        // ...sensitivity, test-gap, churn, coupling, diff-shape, ownership, incident
      ]
    }
  ]
}
```

`schemaVersion` versions the top-level machine contract independently of the CLI release. Empty
diffs emit this same complete shape with zero risk and empty file/exclusion arrays.

The primary score is `riskScore`; human and markdown reports show a derived
`confidence = 100 - riskScore`, but that computed display value is not encoded in
the JSON output. `calibration.confidence` is different: it is the `0...1`
backing factor for history-derived incident evidence.
