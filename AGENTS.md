# AGENTS.md — augur

Guidance for AI agents working in this repository.

## What augur is

A deterministic change-risk engine. It reads a git diff and emits a verdict — `proceed`,
`review`, or `block` — from structural signals only. **No API key, no LLM in the core.**

## Golden rules

1. The core stays AI-free. Never add a hosted-LLM or local-model dependency to `AugurKit`.
   Optional AI lives only in `augur explain`, delegated to `fledge`.
2. `AugurKit` has **zero third-party dependencies**. Keep it that way. Config parsing
   (`.augur.toml` via `TOMLDecoder`) lives in the **CLI target only**: the CLI decodes the
   file, then constructs `RiskEngine(weights:rules:thresholds:)` and injects it into the pure
   engine. Verdict thresholds are configurable via the `Thresholds` type in `AugurKit`.
3. Scoring must stay **deterministic** — no `Date()`/randomness inside the engine; `now` is
   injected at the CLI boundary so tests are reproducible.
4. Every signal must carry a human-readable `detail`. No opaque numbers.
5. Follow CorvidLabs Swift conventions: explicit access control, K&R braces, no force
   unwrap, `async`/`await`, `Sendable`, descriptive generics, strict concurrency.

## Layout

| Path | Role |
|------|------|
| `Sources/AugurKit/` | The engine library (no third-party deps). |
| `Sources/augur/` | The CLI (`swift-argument-parser`). |
| `Tests/AugurKitTests/` | Engine tests via an in-memory `RepositoryProbe`. |
| `specs/change-confidence/` | The spec spec-sync validates against the code. |

## Workflow

```sh
fledge run check     # build + test + spec — run before claiming done
fledge run test
fledge run spec
fledge run selfcheck # run augur on your own changes
```

If you change the public API of `AugurKit`, update
`specs/change-confidence/change-confidence.spec.md` and bump its `version` so
`fledge spec check` passes.

## Adding a signal

1. Add a pure computation in `RiskEngine.assessFile` returning a `Signal` (`risk` 0...1).
2. Add a weight to `RiskEngine.Weights` and keep the weights summing to `1.0`.
3. Add a test in `RiskEngineTests` using `FixtureProbe`.
4. Document it in the README table and the spec's Public API / Behavioral Examples.
