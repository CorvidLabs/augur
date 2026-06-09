# Testing — Change Confidence

## Strategy

The engine is tested through an in-memory `FixtureProbe` conforming to `RepositoryProbe`,
so scoring is verified without invoking `git`. `now` is injected for deterministic recency.

## Coverage (Tests/AugurKitTests/RiskEngineTests.swift)

| Test | Asserts |
|------|---------|
| `testTrivialDocChangeProceeds` | A small docs edit yields `proceed`, risk `< 35`. |
| `testAuthChangeWithoutTestsEscalates` | Sensitive path + missing tests reach at least `review`. |
| `testTestAlongsideLowersRisk` | Touching a test file strictly lowers the source file's risk. |
| `testCalibrationConfidenceGrowsWithHistory` | Confidence `< 0.25` with thin history, `> 0.6` with deep history. |
| `testIncidentHistoryRaisesRiskOnlyWhenCalibrated` | Revert-prone file raises `incident`; calibration `> 0.5`. |
| `testNumstatParsing` | `git diff --numstat` parsing, including binary (`-`) files. |
| `testLogParsing` | Single-pass log parsing and incident-subject detection. |

## Manual / dogfood

- `fledge run selfcheck` — run augur on its own working-tree changes.
- `augur check -C <repo> --range HEAD~1..HEAD` against a repo with real history.
