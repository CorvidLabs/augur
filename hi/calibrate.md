---
hi: 1
families: [CALIBRATE]
---

# Knowing whether to believe it

## Intent

A risk score that will not admit how much it is guessing is worse than no score, so augur should always say what its judgement rests on. On a repository it has just met it should lean only on the reasoning that needs no history, and it should keep the history-based reason silent rather than pretend. As a repository accumulates commits and real incidents, that reason should be allowed to count for more, and the report should show the volume behind it so nobody has to take the number on faith. Because walking a long history is slow and agents run in tight loops, augur should be able to learn once, remember it, and be honest when what it remembered has gone stale.

## Criteria

- **CALIBRATE-1**  Every assessment tells me whether its score is grounded in this repository's history or still resting on defaults.
  - **CALIBRATE-1.a**  I can see how much history stands behind that judgement, in commits and in incidents.
  - **CALIBRATE-1.b**  On a repository with no history to learn from, the history-based reason contributes nothing at all.
  - **CALIBRATE-1.c**  The longer augur watches a repository, the more that reason is allowed to count.
- **CALIBRATE-2**  The part of the score that needs no history always applies, so a brand-new repository still gets a useful verdict.
- **CALIBRATE-3**  I can have augur walk the history once and remember what it learned.
  - **CALIBRATE-3.a**  A later check can reuse that instead of walking the log again.
  - **CALIBRATE-3.b**  A remembered model that has fallen behind the current commit warns me but still works.
  - **CALIBRATE-3.c**  Asking to reuse a model that was never built works it out live rather than failing.
  - **CALIBRATE-3.d**  What augur remembers stays out of my commits.
- **CALIBRATE-4**  A reused model produces exactly the verdict that walking the history fresh would have.
