---
title: "CI integration"
description: "augur gate, the composite action, SARIF upload (GHAS caveat), the pre-commit hook, and the augur → attest trust pipeline."
section: "Integration"
order: 7
---

`augur` is deterministic and needs no API key, so it slots cleanly into CI and
agent loops. Use `augur gate` to fail a job when a verdict crosses a threshold.

> **Scope.** Everything here is **macOS-only** and runs on CorvidLabs'
> self-hosted **macOS ARM64** runners (`runs-on: [self-hosted, macOS]`). The
> composite actions and reusable workflows build augur (and attest) *from a
> checkout* — there is no published binary yet, and cross-repo tool packaging is
> a deliberately deferred later step.

## The one-liner

```yaml
- run: augur gate --range origin/main..HEAD --threshold block
```

`gate` exits `1` when the verdict meets or exceeds the threshold, `0` otherwise
(and on no changes). See [cli.md](cli.md#gate) for exit codes.

## The `augur-gate` composite action

This repo ships a composite GitHub Action ("augur gate", `action.yml`) that
builds augur from the checked-out source and runs `augur gate`. Use it from
augur's *own* workflow to self-gate:

```yaml
jobs:
  gate:
    runs-on: [self-hosted, macOS]
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }   # gate needs history for the range
      - uses: ./
        with:
          range: origin/main..HEAD
          threshold: block
          coverage: lcov.info        # optional
          working-directory: .       # optional
```

| Input | Default | Description |
|-------|---------|-------------|
| `range` | `origin/main..HEAD` | Git range to assess. |
| `threshold` | `block` | Fail at or above this verdict (`proceed` / `review` / `block`). |
| `coverage` | *(none)* | Optional path to an LCOV `.info` or Cobertura `.xml` report. |
| `working-directory` | `.` | Repository root to run in. |

**Deferred:** the action builds augur from *its own checkout*, which is correct
for augur self-gating its CI. Reusing it from *other* repos (installing a
published binary rather than rebuilding) is not wired up yet — don't add
`uses: CorvidLabs/augur@v…` to a foreign repo expecting it to gate that repo.

## SARIF upload (GitHub code scanning)

`augur check --sarif` emits SARIF 2.1.0; `--sarif-out <path>` writes it to a
file. Upload it so verdicts surface as code-scanning annotations on the PR:

```yaml
- run: augur check --range origin/main..HEAD --sarif-out augur.sarif
- uses: github/codeql-action/upload-sarif@v3
  with: { sarif_file: augur.sarif }
```

augur emits a **single** rule, `augur/change-risk`, and **one result per assessed
file**. Each result's `level` is mapped from its verdict:

| Verdict | SARIF level |
|---------|-------------|
| `block` | `error` |
| `review` | `warning` |
| `proceed` | `note` |

The result is regioned on the file's first added line when known. `--sarif` and
`--json` are mutually exclusive; the output is generated entirely in `AugurKit`
with Foundation `Codable` (no third-party SARIF dependency) and is deterministic
(sorted keys).

> **GHAS caveat.** `upload-sarif` requires **GitHub Advanced Security** to be
> enabled — which is free on public repos but a paid add-on on **private** repos.
> On a private repo without GHAS the upload step fails (`403`). The full
> `examples/workflows/sarif.yml` documents this and keeps the gate independent of
> the upload, so you still get a deterministic pass/fail even where GHAS is off.

## Pre-commit hook

`examples/hooks/pre-commit` runs `augur gate --staged --threshold block` and
refuses the commit on a `block` verdict (set `AUGUR_THRESHOLD=review` to also
stop on review-grade changes). Install it from the repo root:

```sh
ln -s ../../examples/hooks/pre-commit .git/hooks/pre-commit
# or copy it: install -m 0755 examples/hooks/pre-commit .git/hooks/pre-commit
git commit --no-verify   # deliberately bypass for one commit
```

## For agents

```sh
verdict=$(augur check --range main..HEAD --json | jq -r .verdict)
[ "$verdict" = "proceed" ] || echo "escalating to a human"
```

## The augur → attest trust pipeline

A verdict from `augur` is *ephemeral* — it lives for one CI run and is gone. Its
sibling [`attest`](https://github.com/CorvidLabs/attest) makes it durable:
`attest` records *who or what reviewed a change, and at what confidence* as a
signed-or-unsigned provenance note keyed to the commit SHA (stored in git notes),
and gates CI / agent loops on a policy. **augur scores the risk; attest records
the trust.** They compose over a pipe and never link to each other:

```sh
augur check --json | attest sign --from-augur -        # record the trust
attest verify --policy .attest.json                     # gate on it
```

`attest sign --from-augur -` copies augur's `verdict` and maps its `riskScore`
(0...100) to `confidence = 1 − riskScore/100`. A worked, end-to-end run is in
`examples/06-trust-pipeline.sh`: an agent attests a `review` change, a policy
demanding human approval for `review`+ verdicts FAILs, then a human signs off and
it PASSes. The policy clears as soon as **any** human-approved attestation exists
on the commit — the human signs off with a plain `--human-approved` and need not
restate the verdict.

### Reusable workflow

`examples/workflows/trust.yml` is a copy-paste GitHub Actions workflow other
CorvidLabs repos can adopt. On `pull_request` it builds augur and runs
`augur gate --range origin/<base>..HEAD --threshold block`, with commented-out
steps showing exactly where `attest sign` / `attest verify` slot in.
