---
title: "Signals"
description: "Every augur signal — what it catches, its weight, and how to tune it."
section: "Reference"
order: 2
---

Every signal is a pure, deterministic function over the change surface and the
repository's git history — no model, no network. Each contributes a `risk` in
`0...1`, carries a documented `weight`, and emits a human-readable `detail`. The
per-file score is the weight-normalized blend; see
[architecture.md](architecture.md) for how the blend and aggregation work.

## The weights

The prior weights sum to `1.0`. They live in `RiskEngine.Weights` and are
overridable per field via `.augur.toml [weights]` (see
[configuration.md](configuration.md)).

| Signal | Weight | What it catches |
|--------|-------:|-----------------|
| [`sensitivity`](#sensitivity) | `0.2024` | Touches secrets, auth, crypto, payments, migrations, infra, CI, or dependency manifests. |
| [`test-gap`](#test-gap) | `0.1656` | Code changed with no test in the changeset — or, with coverage, the uncovered fraction of changed lines. |
| [`churn`](#churn) | `0.1380` | Hot files that change constantly are fragile. |
| [`coupling`](#coupling) | `0.1196` | A file's usual co-change partner is *absent* from the change. |
| [`diff-shape`](#diff-shape) | `0.1104` | Large single-file edits are harder to review. |
| [`ownership`](#ownership) | `0.0920` | Bus-factor (single author) or diffuse ownership (many authors). |
| [`incident`](#incident) | `0.0920` | The file's own history of reverts / hotfixes (calibrated). |
| [`codeowners`](#codeowners) | `0.0800` | A changed file with no declared `CODEOWNERS` owner. |

> **Why these exact decimals?** The `codeowners` signal (added in spec v7) claimed
> a weight of `0.08`. To keep the blend summing to `1.0` *without* changing the
> relative importance of the seven original signals, each of them was scaled by
> `1 − 0.08 = 0.92`. So `sensitivity` went from `0.22` to `0.22 × 0.92 = 0.2024`,
> and so on. The ratios between the original seven are unchanged.

## Signal reference

### sensitivity

Matches the changed path against a configurable ruleset (`SensitivityRuleset`).
The highest-severity matching category sets the risk. Built-in categories, by
descending severity:

| Category | Risk | Example fragments |
|----------|-----:|-------------------|
| secrets | `1.0` | `.env`, `secret`, `credential`, `.pem` |
| auth | `0.9` | `auth`, `login`, `session`, `token`, `oauth` |
| crypto | `0.85` | `crypto`, `encrypt`, `signing`, `keychain` |
| payments | `0.85` | `payment`, `billing`, `stripe`, `checkout` |
| migration | `0.8` | `migration`, `schema`, `/sql/` |
| infra | `0.7` | `dockerfile`, `terraform`, `k8s`, `helm` |
| ci | `0.6` | `.github/workflows`, `.gitlab-ci`, `circleci` |
| dependencies | `0.55` | `package.json`, `cargo.toml`, `go.mod` |

**Tune:** add rules via `.augur.toml [[rules]]` (merged onto defaults), or set
`[sensitivity] replace_defaults = true` to use only your rules.

### test-gap

Without coverage, a coarse heuristic: did the changeset touch *any* test file?
- test file → `0`; binary asset → `0.1`; a sibling test in the changeset → `0.15`;
  code with no test → `0.7`.

With a `--coverage` report it becomes precise for non-test code files:
`risk = 1 − covered/instrumented` over the change's instrumented added lines; a
code file entirely absent from the report scores `0.7`. See
[coverage.md](coverage.md).

**Tune:** supply a coverage report to sharpen it; raise `[weights] test_gap` if
test discipline matters most to you.

### churn

`risk = min(1, recent_commits_touching_file / 40)`. Files that change constantly
are statistically fragile.

**Tune:** the divisor is fixed; adjust importance via `[weights] churn`.

### coupling

If a file's strongest historical co-change partner (seen together `≥ 4` times) is
*absent* from the current change, that's a broken co-change pattern → `0.6`.
Otherwise `0`.

**Tune:** `[weights] coupling`.

### diff-shape

`risk = min(1, lines_touched / 400)` (binary files: `0.2`). Large single-file
edits are harder to review well.

**Tune:** `[weights] diff_shape`.

### ownership

A U-shaped curve on distinct historical authors:

| Authors | Risk | Why |
|---------|-----:|-----|
| 0 | `0.3` | new / untracked file |
| 1 | `0.35` | single author (bus-factor) |
| 2–4 | `0.1` | healthy |
| 5+ | `0.6` | diffuse ownership |

This is the *git-history* ownership signal, distinct from `codeowners` (which is
about declared review routing).

**Tune:** `[weights] ownership`.

### incident

`0.8` if the file appears in commits whose subjects look like reverts / hotfixes
/ fix follow-ups, **multiplied by the calibration confidence**. On a history-free
repo this contributes `0`; in a repo with deep history and real incidents it
sharpens. The detail reports the calibration factor.

**Tune:** `[weights] incident`. Run `augur calibrate` to back it with history.

### codeowners

Flags review-routing gaps using the repo's `CODEOWNERS` file. Behavior:

- **No `CODEOWNERS` file** → `0` (neutral). Repos without one are never penalized.
- **Changed file with no declared owner** → `0.6`, detail `no CODEOWNERS owner`.
- **Owned file** → `0`, detail `owned by @team, @user`.

`augur` auto-discovers `CODEOWNERS` at `.github/CODEOWNERS`, `CODEOWNERS`, or
`docs/CODEOWNERS` (GitHub precedence; first found wins). Matching follows GitHub
semantics — **last matching pattern wins** — and reuses the same `GlobPattern`
engine as path exclusions. Disable with `--no-codeowners`.

```text
# .github/CODEOWNERS
*            @platform        # catch-all
/src/        @backend-team    # overrides the catch-all for src/
/src/auth/   @security        # overrides again for src/auth/
*.md         @docs-team
```

**Tune:** `[weights] codeowners`. Set it to `0` to disable the signal's
contribution entirely while keeping the rest of the blend (or just pass
`--no-codeowners`).
