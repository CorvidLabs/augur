# Context — Change Confidence

## Why this exists

Agents made code cheap to produce; the scarce resource is now *trust*. There is no portable,
language-agnostic, CI-agnostic primitive that answers "how risky is this diff, and should a
human look at it?" That judgment lives in senior engineers' heads. `augur` makes it a
deterministic, scriptable artifact.

## Design decisions

- **Range-first.** A commit range is the native input; working-tree and staged modes are
  expressed as ranges against `HEAD`. This keeps the scoring unit aligned with the revert
  history the calibration trains on — both are commit-shaped.
- **Two-layer score.** A transparent heuristic prior always applies, so a brand-new repo
  still gets a usable verdict. History calibration *adjusts* the prior and is reported via
  `Calibration` so consumers never mistake a prior-only score for a history-backed one.
- **No black box.** Every signal carries a human-readable `detail`. The score is auditable.
- **AI is additive.** The core never calls a model. `augur explain` delegates to `fledge`.

## Non-goals

- Not a task runner, release tool, or spec checker (that's `fledge` / `spec-sync`).
- Not a semantic code-understanding engine; signals are structural, not behavioral.
- Not a replacement for human review — it *routes* attention to where review is warranted.
