---
hi: 1
families: [GATE]
---

# Stopping a risky change

## Intent

Reporting is for people; gating is for pipelines and agents, which need a decision they can act on without reading anything. A gate should be one line in a workflow or a hook, should fail at a threshold the team chose rather than one augur imposed, and should be boring when there is nothing to worry about. It has to be usable by a repository that has never heard of Swift, and safe enough that installing it is not itself a supply-chain risk. Where it stops someone, it should be obvious both what stopped them and how to override it on purpose.

## Criteria

- **GATE-1**  I can ask augur to fail instead of report, so a pipeline stops on a risky change.
  - **GATE-1.a**  I choose the verdict the gate fails at.
  - **GATE-1.b**  A change with nothing in it never fails a gate.
  - **GATE-1.c**  A threshold word augur does not know is a usage error that shows me the valid ones.
- **GATE-2**  The gate prints one line I can take in at a glance in a CI log.
- **GATE-3**  An agent can read the verdict and escalate to a person instead of merging blind.
- **GATE-4**  A commit hook can refuse a block-grade commit before it lands.
  - **GATE-4.a**  I can raise the hook to stop on review-grade changes too.
  - **GATE-4.b**  I can deliberately bypass the hook for a single commit.
- **GATE-5**  I can add a gate to a GitHub workflow in a couple of lines.
  - **GATE-5.a**  The gate brings its own ready-built binary rather than making me set up a toolchain first.
  - **GATE-5.b**  A downloaded binary is checked against its published checksum before anything runs it.
  - **GATE-5.c**  Pinning to a major version never quietly carries me across a major boundary.
  - **GATE-5.d**  A later step in the same workflow can read the verdict and the score without running augur again.
- **GATE-6**  A pull request shows augur's verdict as a check alongside the rest of CI.
- **GATE-7**  Nothing a caller passes into the gate can turn into a shell command.
