# Context — Command-Line Interface

## Why this exists

`AugurKit` is a pure, deterministic, dependency-free engine. Something has to do
the messy work at the edges: parse arguments, read `.augur.toml`, find coverage
and CODEOWNERS files, talk to `git`, detect a TTY, and format output. That is
the CLI's whole job — it is the adapter that turns a real repository and a set of
flags into engine inputs, and an `Assessment` back into text a human or a CI job
can read.

## Design decisions

- **Thin boundary.** The CLI holds every dependency the engine refuses:
  `swift-argument-parser` and `TOMLDecoder` live here, never in `AugurKit`. The
  file is decoded into an `AugurConfig`, which constructs a `RiskEngine` that is
  injected into the pure core.
- **stdout is sacred.** Callers pipe JSON, SARIF, or a report; notes and warnings
  must never contaminate it, so `Diagnostics` writes exclusively to stderr.
- **Fail closed on config.** `TOMLDecoder` silently ignores unknown keys, so a
  typo'd `[[sensitivity.rules]]` would disable a rule without complaint. The CLI
  walks the raw document shape against a known schema and rejects unknown keys
  outright, because a security tool that silently drops a rule is worse than one
  that errors.
- **Additive configuration.** An absent or empty `.augur.toml` equals the
  built-in defaults; every section overrides only the fields it names.
- **AI stays out.** `explain` shells out to `fledge ask`; the CLI never links a
  model, keeping the "core is AI-free" rule true all the way to the executable.
