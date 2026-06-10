# Changelog

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

