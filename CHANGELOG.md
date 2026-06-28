# Changelog

## [v0.4.1] - 2026-06-28

### Fixes

- publish linux homebrew formula updates (#39) (7f9e9a3)

### Other

- Update: bump CLI version to 0.4.1 (0ff39ce)
- Update CLI demo GIF (#42) (f6e5476)
- Fix all-zero GitHub push range diagnostic (#41) (f06b8e9)
- Update: standardize GitHub Actions (path filters, concurrency, runners) (#37) (6c40129)
- Update hub.ts (#36) (38e85d5)
- Retire: redirect the standalone augur site to the CorvidLabs hub (#35) (7e093f8)

## [v0.4.0] - 2026-06-11

### Changed

- `AugurError.git` now carries the failing command, exit status, and git's stderr (`case git(command:status:stderr:)`); source-breaking for `AugurKit` consumers that match on it

### Fixed

- Untracked (never-`git add`ed) files are now included in working-tree assessments as fully-added files, so a brand-new file can no longer score zero risk by being invisible to `augur check`
- Unknown/typo'd `.augur.toml` keys are now a hard error naming the offending key path and its valid siblings (a typo'd `[[sensitivity.rules]]` used to be silently ignored, failing open)
- A coverage file that parses to zero records is rejected instead of "loading" silently; a missing coverage file now says it does not exist instead of "could not detect format" (auto-detected files warn and fall back)
- The test-gap signal no longer fires on documentation files (`.md`, `.rst`, `.txt`, `LICENSE`, ...), so docs-only changes can score near zero
- Failing git invocations now include git's own stderr message (e.g. `fatal: ambiguous argument ...`), and malformed `.augur.toml` decode errors render as human-readable key-path messages instead of raw Swift `DecodingError` dumps
- Conflicting scope flags (`--staged` with `--range`) are now a usage error (exit 64) instead of silently preferring the range
- An invalid `gate --threshold` value now prints gate's own usage instead of the generic root usage
- Pluralization: "1 incident / 1 commit" (and "1 line touched") instead of "1 incidents / 1 commits"

## [v0.3.2] - 2026-06-10

### Other

- CI hardening: guard major-lookup jq + block self-hosted runners (#31) (9004aeb)
- Fix: statically link the Linux release binary (--static-swift-stdlib) (#29) (e4f8c75)
- Add: CI Linux packaging smoke + restrict Release to dotted version tags (#30) (bf55e18)
- Add: CI smoke-test that dogfoods the composite action (1e1953d)

## [v0.3.1] - 2026-06-10

### Other

- Release v0.3.1: bump CLI version (36a3d35)
- Add: Marketplace-ready GitHub Action that gates any repo (#28) (1f77f81)
- Fix: skip formula auto-bump gracefully when TAP_GITHUB_TOKEN is unset (23121f9)

## [v0.3.0] - 2026-06-10

### Other

- Release v0.3.0: bump CLI version (c7067f5)
- Add: Linux support (build + test on macOS and Linux) (#27) (7f4bb19)
- Add: animated demo GIF to README and site hero (#26) (cf4fc48)
- Security: move CI off self-hosted runners to GitHub-hosted (#25) (f95c61e)
- Fix: read the hero badge version from CHANGELOG so it does not drift (#24) (81ba253)
- Add: release binary + brew formula automation, lead with brew, decouple Pages from self-hosted (#23) (a770b9b)
- Fix: rebuild the site on CHANGELOG changes so the version badge stays accurate (#22) (8fe97e9)

## [v0.2.1] - 2026-06-09

### Other

- Release v0.2.1: bump CLI version (073b2be)
- Fix: report excluded paths when the filter excludes every changed file (#21) (3e71ef3)

## [v0.2.0] - 2026-06-09

### Other

- Release v0.2.0: bump CLI version (3798e16)
- Fix: anchor dir/** glob at a path boundary (was over-matching siblings) (#20) (429a5d9)
- Fix: resolve renamed and non-ASCII paths in the git layer (#19) (cb54a24)
- Fix: trust-pipeline demo now reliably scores review so the gate story holds (#18) (bd5afde)
- Add: Quickstart and a live-examples index (#17) (532b940)
- Exclude test snapshot goldens from SwiftPM target (#16) (1dfb5b2)
- Add: markdown report, sticky PR comment, and PR risk summary (#15) (ead120b)
- Add: commit-status check + live Pages badge for augur (#14) (367166d)
- Chore: rewrite docs/site copy in plain voice, drop em-dashes (#13) (c2153b2)
- Add: augur self-dogfooding (CI + examples/dogfood.sh + docs/dogfooding.md) (#12) (35aaf02)
- Add: terminal snapshot tests + site mockups accurate to colored output (#11) (3256faf)
- Add: colorful terminal output for augur (NO_COLOR/TTY-aware) (#10) (9a6cdc4)
- Chore: Node 24 workflow opt-in + review polish (#9) (d2a716c)
- Fix: align CLI version to the v0.1.0 release tag (#8) (7075d02)
- Add: Astro GitHub Pages marketing + docs site (#7) (8a33375)

## [v0.1.0] - 2026-06-09

### Other

- Add: CODEOWNERS-aware ownership signal, expanded tests, and docs/ (#6) (de0153e)
- Add: path exclusions (.augur.toml [exclude] + --exclude globs) (#5) (10fd918)
- Add: JaCoCo and Go coverprofile coverage ingestion (#4) (99c68e2)
- Fix: update trust-pipeline docs for corrected human-approval policy (#3) (e231246)
- Add: SARIF 2.1.0 output for GitHub code scanning (#2) (43cdad8)
- Add: augur↔attest trust-pipeline demo, reusable CI workflow, pre-commit hook (#1) (676d076)
- Add: per-line coverage ingestion + augur-gate composite action (3a28011)
- Add: configurable .augur.toml rules + augur calibrate cache (ab2867d)
- Add: augur - deterministic change-confidence & risk engine (31ee79b)

