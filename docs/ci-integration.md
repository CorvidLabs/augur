# CI integration

`augur` is deterministic and needs no API key, so it slots cleanly into CI and
agent loops. Use `augur gate` to fail a job when a verdict crosses a threshold.

> **Scope.** Everything here is **macOS-only** and runs on CorvidLabs'
> self-hosted **macOS ARM64** runners (`runs-on: [self-hosted, macOS]`). The
> composite actions and reusable workflows build augur (and attest) *from a
> checkout*. There is no published binary yet, and cross-repo tool packaging is
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
| `coverage` | *(none)* | Optional path to a coverage report (LCOV `.info`, Cobertura/JaCoCo `.xml`, or Go `.out` coverprofile). |
| `working-directory` | `.` | Repository root to run in. |

**Deferred:** the action builds augur from *its own checkout*, which is correct
for augur self-gating its CI. Reusing it from *other* repos (installing a
published binary rather than rebuilding) is not wired up yet, so don't add
`uses: CorvidLabs/augur@v…` to a foreign repo expecting it to gate that repo.

## Commit status (verdict in the GitHub web UI)

augur's own CI (`.github/workflows/ci.yml`) posts its self-assessment as a
GitHub **commit status** so the verdict shows up as a check on the commit and PR
pages, next to the rest of CI. The job grants `statuses: write` and, after the
gate step, computes the verdict from
`augur check --range <range> --json` (range `origin/main..HEAD`, falling back to
`HEAD~1..HEAD`), then posts it:

```sh
gh api -X POST repos/<owner>/<repo>/statuses/<sha> \
  -f state=<success|failure> \
  -f context=augur \
  -f description="<verdict> · risk <N>/100" \
  -f target_url="https://github.com/<owner>/<repo>/actions/runs/<run_id>"
```

State mapping: `proceed`/`review` → `success`, `block` → `failure`, so a
block-level change shows a red `augur` check. The SHA is the PR head
(`github.event.pull_request.head.sha`) or `github.sha` on a push. The step is
best-effort (`|| echo "status post skipped"`) so a token or permission hiccup can
never redden CI, and an empty/first-commit range is skipped cleanly. It uses the
default `GITHUB_TOKEN`, which is sufficient given `statuses: write`.

## Live README badge (served from GitHub Pages)

The README's `augur` badge is a shields.io
[endpoint badge](https://shields.io/endpoint) backed by a JSON file the Pages
build publishes at the site root:

```
https://corvidlabs.github.io/augur/badge.json
```

`.github/workflows/pages.yml` runs the build job on `[self-hosted, macOS]` (so the
Swift toolchain is available) and, **before** the Astro build, builds the release
binary, runs `augur check --range HEAD~1..HEAD --json` on the repo, and writes
`site/public/badge.json` in the shields endpoint schema:

```json
{ "schemaVersion": 1, "label": "augur", "message": "<verdict>", "color": "<color>" }
```

Color map: `proceed → brightgreen`, `review → yellow`, `block → red`. An empty
range (first commit) falls back to `message: "ready", color: "blue"`. Astro copies
`site/public/*` to the published root, so the file lands at `site/dist/badge.json`
and serves at the URL above. The deploy job stays on `ubuntu-latest` (it only
uploads the built artifact and needs no Swift toolchain). The README references
the endpoint with:

```md
[![augur](https://img.shields.io/endpoint?url=https://corvidlabs.github.io/augur/badge.json)](https://corvidlabs.github.io/augur/)
```

> **Private-repo caveat.** As noted in `pages.yml`, serving Pages from a private
> repo to a public URL needs a paid GitHub plan; until the repo is public (or a
> plan is enabled) the badge JSON will not publish, and the endpoint badge will
> show shields.io's "inaccessible" state. Everything is built and ready.

## SARIF upload (GitHub code scanning)

`augur check --sarif` emits SARIF 2.1.0; `--sarif-out <path>` writes it to a
file. Upload it so verdicts surface as code-scanning annotations on the PR:

```yaml
- run: augur check --range origin/main..HEAD --sarif-out augur.sarif
- uses: github/codeql-action/upload-sarif@v3
  with: { sarif_file: augur.sarif }
```

Each assessed file becomes one SARIF `result` under the single rule
`augur/change-risk`, with `level` mapped from its verdict (`block → error`,
`review → warning`, `proceed → note`) and the result regioned on the file's first
added line when known.

> **GHAS caveat.** `upload-sarif` requires **GitHub Advanced Security** to be
> enabled. That is free on public repos but a paid add-on on **private** repos.
> On a private repo without GHAS the upload step fails. The full
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

A verdict from `augur` is *ephemeral*: it lives for one CI run and is gone. Its
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
[`examples/06-trust-pipeline.sh`](../examples/06-trust-pipeline.sh): an agent
attests a `review` change, a policy demanding human approval for `review`+
verdicts FAILs, then a human signs off and it PASSes. The policy clears as soon
as **any** human-approved attestation exists on the commit.

### Reusable workflow

[`examples/workflows/trust.yml`](../examples/workflows/trust.yml) is a copy-paste
GitHub Actions workflow other CorvidLabs repos can adopt. On `pull_request` it
builds augur and runs `augur gate --range origin/<base>..HEAD --threshold block`,
with commented-out steps showing exactly where `attest sign` / `attest verify`
slot in.
