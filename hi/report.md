---
hi: 1
families: [REPORT]
---

# Handing the verdict on

## Intent

A verdict is only useful where the decision is being made, which is often not a terminal: it is an agent's script, a pull-request comment, or the annotations beside the diff. augur should be able to hand the same judgement to each of those in the shape that place expects, without anyone parsing human text. The machine shapes need to be stable enough to diff and version enough to evolve, and they should never quietly drop anything — what was excluded, and what an empty change looks like, must be as visible as the score. Anything augur wants to mention to a person goes somewhere other than the stream being piped.

## Criteria

- **REPORT-1**  I can get the whole assessment as JSON a script or an agent can read.
  - **REPORT-1.a**  The keys come out in a stable order, so two runs diff cleanly.
  - **REPORT-1.b**  The JSON says which version of its shape it is, so a consumer can tell when it changes.
  - **REPORT-1.c**  An empty change produces the same shape as any other, not a special reduced object.
  - **REPORT-1.d**  The JSON lists what was left out of the assessment, so nothing disappears quietly.
- **REPORT-2**  I can get a markdown report to drop into a pull request or a job summary.
  - **REPORT-2.a**  The markdown leads with the verdict, then a riskiest-first table of files.
  - **REPORT-2.b**  A CI job can update the same pull-request comment in place instead of piling up new ones.
  - **REPORT-2.c**  A sprawling change shows only the riskiest rows, with a count of how many more there were.
- **REPORT-3**  I can get SARIF so the verdict lands as inline annotations on a pull request.
  - **REPORT-3.a**  Each annotation sits on the first line the change added to that file.
  - **REPORT-3.b**  A block reads as an error, a review as a warning, and a proceed as a note.
  - **REPORT-3.c**  I can write machine output straight to a file for a later step to pick up.
- **REPORT-4**  Asking for two output formats at once is refused rather than guessed at.
- **REPORT-5**  Notes and warnings never land in the stream I am piping.
