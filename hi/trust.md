---
hi: 1
families: [TRUST]
---

# Making a verdict durable

## Intent

A verdict lives for one CI run and then vanishes, which is fine for a gate and useless for an audit. The score should therefore be shaped so that something else can record it against the commit it judged, turning a moment's judgement into a standing claim about who or what reviewed this change and how confident they were. augur should stay the thing that scores and never become the thing that keeps the record; the two should meet over a pipe and owe each other nothing. Because this is the part people are most likely to disbelieve, it should be demonstrated running rather than described.

## Criteria

- **TRUST-1**  I can keep a verdict beyond the run that produced it, recorded against the commit it judged.
- **TRUST-2**  I can hand a verdict straight to the tool that keeps the record, without translating the score myself.
- **TRUST-3**  I can choose where that record lives, because augur scores changes and never keeps the record itself.
- **TRUST-4**  A risky change can be made to wait for a person's sign-off before it merges.
  - **TRUST-4.a**  A person's sign-off clears the wait without their having to restate the verdict.
- **TRUST-5**  I can watch the whole loop run end to end, with real commands and real exit codes, rather than take it on description.
