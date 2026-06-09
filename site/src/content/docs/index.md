---
title: "augur docs"
description: "Graded trust for code changes — deterministic risk scoring for humans and AI agents. No API key, no LLM."
section: "Getting started"
order: 0
---

`augur` reads a git diff and tells you how risky it is — and whether a human
should look — as a deterministic, scriptable verdict: `proceed`, `review`, or
`block`. **No API key, no LLM in the core.** AI is optional and additive.

It's built for the world where agents write most of the code: humans can't
hand-review the volume, and agents have no native sense of "I'm out of my depth
here, escalate." `augur` is that missing primitive — language-agnostic and
CI-agnostic.

- **Humans** use it to triage: spend review attention on the risky 10% of a 40-file PR.
- **Agents** use it to gate: `augur gate` exits non-zero so an agent escalates instead of merging blind.

---

## Quick start

```sh
swift build -c release
install -m 0755 .build/release/augur /usr/local/bin/augur

augur check                         # assess working-tree changes
augur check --range main..HEAD      # assess a range (range-first)
augur gate --threshold review       # exit 1 if verdict >= review (CI / agents)
```

Requires Swift 6 and `git` on `PATH`. `augur` is macOS-only.

---

## How it scores

Every signal is derived from `git` history and the filesystem — no model, no network:

| Signal | What it catches |
|--------|-----------------|
| **sensitivity** | Touches secrets, auth, crypto, payments, migrations, infra, CI, or dependency manifests. |
| **test-gap** | Code changed with no test in the changeset — or, with a coverage report, the fraction of changed lines left uncovered. |
| **churn** | Hot files that change constantly are fragile. |
| **coupling** | A file's usual co-change partner is *absent* from the change. |
| **diff-shape** | Large single-file edits are harder to review. |
| **ownership** | Bus-factor (single author) or diffuse ownership (many authors). |
| **incident** | The file's own history of reverts / hotfixes. |
| **codeowners** | A changed file with no declared owner in the repo's `CODEOWNERS`. |

Scoring has two layers: a **transparent heuristic prior** with documented weights
(always applies, even on a brand-new repo), and a **history calibration** that
scales the incident signal by how much the repository's own revert/hotfix record
backs it. Every assessment reports `calibration` (`prior-only` → `weak` →
`history-backed`) so you know whether a score is guessing or grounded.

---

## Learn more

| New to augur? | Going deeper |
|:--------------|:-------------|
| [Quickstart](quickstart.md) — install and first verdict | [Signals](signals.md) — every signal, weight, and tuning knob |
| [CLI reference](cli.md) — every command and flag | [Configuration](configuration.md) — the full `.augur.toml` reference |
| [Architecture](architecture.md) — `AugurKit` vs the CLI, the pipeline | [Coverage](coverage.md) — LCOV / Cobertura / JaCoCo / Go |
| [CI integration](ci-integration.md) — gate, SARIF, pre-commit, attest | [Dogfooding](dogfooding.md) — augur scores augur (real captured proof) |
| [View on GitHub](https://github.com/CorvidLabs/augur) | |
