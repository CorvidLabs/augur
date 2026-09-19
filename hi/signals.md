---
hi: 1
families: [SIGNALS]
---

# Why a change looks risky

## Intent

A verdict nobody can argue with is a verdict nobody can trust, so augur should always be able to point at the specific thing that worried it. The reasons are the ones a senior reviewer would give without thinking: this touches the auth code, this arrived without a test, this file is rewritten every week, this file is the one we keep reverting, nobody is listed to review this. Every one of them should be derived from the repository in front of it rather than from anything external, and every one should come out as a sentence rather than a number. Where a reason would be unfair — prose that cannot carry tests, a repo that never declared owners — it should simply stay quiet.

## Criteria

- **SIGNALS-1**  Every reason augur gives comes from the repository itself: the diff, the files, and the git history.
- **SIGNALS-2**  A change that touches secrets, auth, crypto, payments, migrations, infrastructure, CI, or dependency manifests is flagged for what it touches.
  - **SIGNALS-2.a**  When a path matches more than one sensitive category, the most severe one decides.
- **SIGNALS-3**  Code that changes with no test anywhere in the changeset is treated as riskier than code that arrives with one.
  - **SIGNALS-3.a**  Documentation and prose are never penalized for carrying no tests.
  - **SIGNALS-3.b**  A binary asset is not held to a source file's testing expectation.
- **SIGNALS-4**  A file the repository rewrites constantly is treated as more fragile than one that sits still.
- **SIGNALS-5**  When a file's usual companion is missing from the change, that gap is named.
- **SIGNALS-6**  A very large edit to a single file is treated as harder to review than a small one.
- **SIGNALS-7**  A file only one person has ever touched raises a bus-factor concern.
  - **SIGNALS-7.a**  A file that dozens of people have touched raises the opposite concern.
- **SIGNALS-8**  A file that keeps turning up in reverts and hotfixes carries that record into its score.
- **SIGNALS-9**  A changed file with nobody declared to review it is flagged as a routing gap.
  - **SIGNALS-9.a**  A repository that declares no owners at all is never penalized for it.
  - **SIGNALS-9.b**  An owned file names its owners, so I know who to ask.
  - **SIGNALS-9.c**  I can take declared ownership out of the picture for a run.
- **SIGNALS-10**  Every reason carries a sentence, never a bare number.
- **SIGNALS-11**  I can look up what every reason is worth in the score, so a verdict is never a black box.
