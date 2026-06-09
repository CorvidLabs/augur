# augur examples

Every example here is **self-contained**: it builds the `augur` binary and runs it
against a throwaway git repo under `/tmp`, so you see real output in seconds with no
setup and no risk to your own repos.

```sh
bash examples/01-check.sh
```

## Start here

- **[`01-check.sh`](01-check.sh)**: the simplest run, one `augur check`, human + JSON.
- **[`06-trust-pipeline.sh`](06-trust-pipeline.sh)**: the full `augur → attest` trust loop,
  end to end with real exit codes.

## Catalog

Ordered simplest to most advanced.

| Example | What it shows | Run |
|---------|---------------|-----|
| [`01-check.sh`](01-check.sh) | A single `augur check` against a fresh scratch repo: human report, verbose signals, and JSON. | `bash examples/01-check.sh` |
| [`02-gate-ci.sh`](02-gate-ci.sh) | `augur gate` exit codes at each threshold, for CI steps and agent loops. | `bash examples/02-gate-ci.sh` |
| [`03-calibrate-and-cached.sh`](03-calibrate-and-cached.sh) | `augur calibrate` caches the history model to `.augur/cache.json`; `check --cached` reuses it. | `bash examples/03-calibrate-and-cached.sh` |
| [`04-custom-config.sh`](04-custom-config.sh) | How an `.augur.toml` (tighter thresholds + a custom sensitivity rule) changes the verdict for the same diff. | `bash examples/04-custom-config.sh` |
| [`05-coverage.sh`](05-coverage.sh) | Per-line coverage (LCOV, Cobertura) sharpens the test-gap signal: covered lines lower it, uncovered raise it. | `bash examples/05-coverage.sh` |
| [`06-trust-pipeline.sh`](06-trust-pipeline.sh) | The end-to-end `augur → attest` trust loop: score, record provenance, gate on a policy, human sign-off. Needs `../attest` (skips cleanly if absent). | `bash examples/06-trust-pipeline.sh` |
| [`07-sarif.sh`](07-sarif.sh) | `augur check --sarif` emits a SARIF 2.1.0 log for GitHub code scanning; the script validates it parses. | `bash examples/07-sarif.sh` |
| [`08-coverage-formats.sh`](08-coverage-formats.sh) | The other two coverage formats: JaCoCo XML and Go coverprofile, covered vs uncovered. | `bash examples/08-coverage-formats.sh` |
| [`09-exclude.sh`](09-exclude.sh) | Drop generated/vendored noise from the verdict via `--exclude` and `[exclude]` in `.augur.toml`. | `bash examples/09-exclude.sh` |
| [`10-codeowners.sh`](10-codeowners.sh) | CODEOWNERS-aware ownership: an unowned changed file raises the `codeowners` signal; an owned one neutralizes it. | `bash examples/10-codeowners.sh` |
| [`dogfood.sh`](dogfood.sh) | augur runs augur on itself: a real PROCEED on its own change, plus a caught risky change with a non-zero gate. | `bash examples/dogfood.sh` |

## Notes

- **`06-trust-pipeline.sh`** needs the sibling [`attest`](https://github.com/CorvidLabs/attest)
  repo at `../attest`. If it is missing the script skips cleanly rather than failing.
- All scripts succeed with exit `0`. Where a non-zero `gate` exit is the *point*
  (`02`, `06`, `dogfood`), it is captured and surfaced as data, not a script failure.
- Shared scratch-repo helpers live in [`lib.sh`](lib.sh); copy-paste CI workflows are in
  [`workflows/`](workflows/) and a pre-commit hook is in [`hooks/`](hooks/).
