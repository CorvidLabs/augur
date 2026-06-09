# augur

**Graded trust for changes.** `augur` reads a diff and tells you how risky it is — and
whether a human should look — as a deterministic, scriptable verdict: `proceed`, `review`,
or `block`.

It's built for the world where agents write most of the code: humans can't hand-review the
volume, and agents have no native sense of "I'm out of my depth here, escalate." `augur` is
that missing primitive — language-agnostic, CI-agnostic, and **requiring no API key and no
LLM**. AI is optional and additive.

```
$ augur check --range main..HEAD

augur · main..HEAD

  verdict     [!] REVIEW
  risk        [#########           ]  45/100
  confidence  55/100
  calibration history-backed (156 incidents / 500 commits)

  files (1), riskiest first:
    !    45  src/auth/token.swift
          · sensitivity: matches sensitive category 'auth'

  → an agent should request human review before merging
```

## Why it exists

Agents made code cheap to produce. The scarce resource is now *trust*. `augur` turns the
senior-engineer instinct — "this part is fine, that part needs a careful look" — into a
deterministic artifact that both humans and agents can act on.

- **Humans** use it to triage: spend review attention on the risky 10% of a 40-file PR.
- **Agents** use it to gate: `augur gate` exits non-zero so an agent escalates instead of
  merging blind.

## How it scores

Every signal is derived from `git` history and the filesystem — no model, no network:

| Signal | What it catches |
|--------|-----------------|
| **sensitivity** | Touches secrets, auth, crypto, payments, migrations, infra, CI, or dependency manifests. |
| **test-gap** | Code changed with no test in the changeset. |
| **churn** | Hot files that change constantly are fragile. |
| **coupling** | A file's usual co-change partner is *absent* from the change. |
| **diff-shape** | Large single-file edits are harder to review. |
| **ownership** | Bus-factor (single author) or diffuse ownership (many authors). |
| **incident** | The file's own history of reverts / hotfixes. |

Scoring has two layers:

1. A **transparent heuristic prior** with documented weights — always applies, even on a
   brand-new repo.
2. A **history calibration** that scales the incident signal by how much the repository's
   own revert/hotfix record backs it. Every assessment reports `calibration`
   (`prior-only` → `weak` → `history-backed`) so you know whether a score is guessing or
   grounded. The longer `augur` watches a repo, the sharper it gets.

## Install

```sh
swift build -c release
install -m 0755 .build/release/augur /usr/local/bin/augur
# or, with fledge:
fledge run install
```

Requires Swift 6 and `git` on `PATH`.

## Usage

```sh
augur check                         # assess working-tree changes
augur check --range main..HEAD      # assess a range (range-first)
augur check --staged                # assess staged changes (pre-commit)
augur check --json                  # machine-readable, sorted-key JSON
augur check -v                      # show every contributing signal

augur gate --threshold review       # exit 1 if verdict >= review (CI / agent loops)
augur explain                       # optional AI explanation via fledge

augur calibrate                     # cache the history model to .augur/cache.json
augur check --cached                # reuse the cache instead of re-walking git log

augur check --config ./my.toml      # use an explicit .augur.toml
augur check --no-config             # ignore any .augur.toml; use built-in defaults
```

### Configuration (`.augur.toml`)

Drop an `.augur.toml` at the repo root and `augur` discovers it automatically (override
with `--config <path>`, ignore with `--no-config`). Every section is optional — an absent
file means built-in defaults, so configuration is strictly additive. It is parsed in the
CLI layer only; the engine library stays dependency-free.

```toml
# Verdict cutoffs (0...100). score >= block -> block; >= review -> review; else proceed.
# Defaults: review = 35, block = 65.
[thresholds]
review = 35
block = 65

# Signal weights for the heuristic prior. Only listed keys are overridden.
[weights]
sensitivity = 0.25
test_gap = 0.20

# Set true to use ONLY the custom rules below; default false MERGES them onto the built-ins.
[sensitivity]
replace_defaults = false

# Custom sensitivity rules: flag paths containing any fragment with the given risk (0...1).
[[rules]]
label = "internal-api"
risk = 0.7
fragments = ["internal/", "private/"]
```

A worked, commented config and runnable scripts live in [`examples/`](examples/).

### Calibrate & cache

`augur calibrate` walks git history once and writes a serializable model to
`.augur/cache.json` (pinned to the current `HEAD`), reporting the backing volume and
calibration band. `augur check --cached` then reuses that model instead of re-running
`git log` — ideal for tight agent loops. If `HEAD` has moved since calibration, `check
--cached` prints a staleness warning to stderr but stays usable; with no cache it falls
back to live computation. `.augur/` is git-ignored and never committed.

```sh
augur calibrate           # -> .augur/cache.json (HEAD-pinned)
augur check --cached      # fast path; warns on stderr if stale
```

### In CI

```yaml
- run: augur gate --range origin/main..HEAD --threshold block
```

### For agents

```sh
verdict=$(augur check --range main..HEAD --json | jq -r .verdict)
[ "$verdict" = "proceed" ] || echo "escalating to a human"
```

## JSON shape

```json
{
  "scope": "main..HEAD",
  "riskScore": 45.0,
  "verdict": "review",
  "confidence": 55.0,
  "calibration": { "confidence": 1.0, "totalCommits": 500, "incidentCommits": 156 },
  "thresholds": { "review": 35.0, "block": 65.0 },
  "files": [
    { "path": "src/auth/token.swift", "riskScore": 45.0, "signals": [ /* ... */ ] }
  ]
}
```

## Development

```sh
fledge run check     # build + test + spec check
fledge run test
fledge run spec      # spec-sync alignment
fledge run selfcheck # dogfood: run augur on its own changes
```

The engine (`AugurKit`) has **zero third-party dependencies** and is fully testable without
`git` via the `RepositoryProbe` protocol. The CLI uses `swift-argument-parser`.

## Roadmap

- [x] `augur calibrate` — cache the history model; report backing volume (`check --cached`).
- [x] Configurable sensitivity rules, weights, and verdict thresholds (`.augur.toml`).
- [ ] Coverage-report ingestion (lcov/cobertura) for per-line test-gap precision.
- **`attest`** — signed provenance records keyed to commit SHAs: a verifiable trail of
  *what reviewed a change and at what confidence*. `augur` says how much to trust a change;
  `attest` records that trust.

## License

MIT © CorvidLabs
