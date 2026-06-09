---
title: "Dogfooding"
description: "augur scores augur: real captured proof of a PROCEED on its own change and a caught risky change, plus an honest note on calibration."
section: "Integration"
order: 8
---

augur is a change-risk engine, so the most honest test is the obvious one:
**augur runs augur on its own changes**, in CI and in a committed, runnable
demo. Every block of output below is real, produced by the release binary
(`swift build -c release`) on this repository, not hand-written.

Reproduce any of it:

```sh
fledge run dogfood          # build release + assess & gate augur's last commit
./examples/dogfood.sh       # the full proof: PROCEED on self + caught risky change
```

## 1. augur trusts its own change (PROCEED)

Running the release binary over augur's latest change
(`augur check --range HEAD~1..HEAD`) yields a low-risk **PROCEED**: the
structural signals see a routine, well-tested diff:

```
augur · HEAD~1..HEAD

  verdict     [ok] PROCEED
  risk        [#####               ]  23/100
  confidence  77/100
  calibration prior-only (2 incidents / 15 commits)

  files (17), riskiest first:
    ·     9  Tests/AugurKitTests/ReporterSnapshotTests.swift
          · diff-shape: 188 lines touched
    ·     7  site/src/content/docs/cli.md
          · ownership: single author (bus-factor)
    ·     7  site/src/pages/index.astro
          · ownership: single author (bus-factor)
    ...
```

The corresponding `block` gate passes, so a PROCEED self-change never reddens
CI:

```
augur gate · proceed (risk 23)
  → augur self-gate at --threshold block: gate exit 0
```

## 2. augur catches a risky change (REVIEW + non-zero gate)

The demo then builds a controlled risky change in a throwaway `/tmp` repo: a
sensitive secrets/auth file with a hard-coded credential plus a large block of
untested functions, exactly what the `sensitivity`, `diff-shape`, and
`test-gap` signals exist to flag. augur returns **REVIEW** and names the reason:

```
augur · <BASE>..<HEAD>

  verdict     [!] REVIEW
  risk        [########            ]  38/100
  confidence  62/100
  calibration prior-only (1 incidents / 11 commits)

  files (1), riskiest first:
    !    38  src/auth/secrets.swift
          · sensitivity: matches sensitive category 'secrets'

  → an agent should request human review before merging
```

Gating that change at `--threshold review` **exits non-zero, for real**. This
is the load-bearing proof: the gate's exit code is captured and expected, not a
script failure.

```
augur gate · review (risk 38)
  → risky-change gate at --threshold review: gate exit 1
```

The `examples/dogfood.sh` summary makes the two outcomes explicit, and the
script itself exits `0` (the gate's `1` is data, not a crash):

```
  augur on augur          : PROCEED-level, block gate passed (exit 0)
  augur on risky change   : REVIEW-level, review gate exit 1 (non-zero = caught)

augur dogfooded itself: trusted its own change AND caught a risky one.
```

## 3. An honest note on calibration

Notice the calibration line in every run above:

```
  calibration prior-only (2 incidents / 15 commits)
```

`prior-only` means augur is scoring from its **heuristic prior** alone. It has
not blended in a learned, repo-specific calibration model. That is the *honest*
state for this repository, and worth explaining rather than hiding:

- augur's history is **squash-merged** (every PR lands as a single commit on
  `main`), so the linear history is short and carries few distinguishable
  "incident" signals (reverts, hotfixes). With so few commits, augur
  deliberately declines to over-fit a calibration model and falls back to the
  deterministic prior.
- **The prior still works.** Both verdicts above (PROCEED on a routine change,
  REVIEW on a secrets file) come straight from the structural signals, with no
  learned history required. augur is useful from commit one.
- **Calibration sharpens as history grows.** On a repo with a longer,
  non-squashed history (or after `augur calibrate` walks more commits), augur
  blends the repo's own revert/incident rate into the score and the calibration
  line graduates from `prior-only` to a blended model.

In short: squash-merging keeps augur's *own* calibration thin, but the engine
is honest about it and degrades gracefully to the prior, exactly the behavior
you want a risk tool to have on a young repository.

## 4. Optional: record the verdict as durable trust (augur → attest)

A verdict is *ephemeral*: it lives for one CI run. The sibling tool
[`attest`](https://github.com/CorvidLabs/attest) makes it durable by recording
*who or what reviewed a change, and at what confidence* as a provenance note
keyed to the commit SHA, then gating CI on a policy. They compose over a pipe:

```sh
augur check --json | attest sign --from-augur -   # record the trust
attest verify --policy .attest.json                # gate on it
```

A full, real-exit-code walkthrough lives in `examples/06-trust-pipeline.sh`
on [GitHub](https://github.com/CorvidLabs/augur/blob/main/examples/06-trust-pipeline.sh):
an agent attests a `review` change, a policy that demands human approval for
`review`+ verdicts FAILs, then a human signs off and it PASSes.

## Where this runs

- **CI** (`.github/workflows/ci.yml`): after `swift build` / `swift test` /
  `fledge spec check`, CI builds the release binary, prints augur's verdict on
  its own change (`origin/main..HEAD`, falling back to `HEAD~1..HEAD`), then
  runs `augur gate --threshold block` as a **fatal** step: a genuinely
  block-level self-change fails CI, while proceed/review pass.
- **Local** (`fledge run dogfood`): the same assess-and-gate, reproducible on
  your machine.
- **Demo** (`examples/dogfood.sh`): the committed, runnable proof captured on
  this page.
