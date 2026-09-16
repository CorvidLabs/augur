---
hi: 1
families: [START]
---

# Starting out

## Intent

augur should be the easiest thing in a risk-conscious toolchain to adopt: one install, no account, no key, nothing to configure, and no dependency on the language the repository happens to be written in. The piece that decides whether a change is safe should carry as little borrowed code as possible, because that is exactly the piece nobody wants a supply-chain surprise in. It has to be fast enough to sit in a pre-commit hook and in an agent's inner loop without anyone noticing it. And since it claims to judge changes, it should be seen judging its own, with the evidence committed rather than asserted.

## Criteria

- **START-1**  I can start using augur with no API key, no model, and no network call.
  - **START-1.a**  The part that decides whether my change is safe carries no third-party code.
- **START-2**  Getting augur onto my machine is one command.
- **START-3**  git on my PATH is the only thing augur needs in order to run.
- **START-4**  I get the same kind of verdict whatever language the repository is written in.
- **START-5**  Everything augur can do has a runnable example sitting beside it.
  - **START-5.a**  An example runs against a throwaway repository, so trying one touches nothing of mine.
- **START-6**  augur is quick enough to sit in a commit hook and in an agent's inner loop.
- **START-7**  augur judges its own changes with its own gate.
  - **START-7.a**  The proof that it does is committed and runnable, not asserted.
- **START-8**  I can ask for an AI explanation of an assessment when I want one.
  - **START-8.a**  augur tells me plainly that I never need the AI explanation.
  - **START-8.b**  Without the AI helper installed, I still get the assessment.
