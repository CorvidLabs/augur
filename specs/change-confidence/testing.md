# Testing — Change Confidence

## Strategy

The engine is tested through an in-memory `FixtureProbe` conforming to `RepositoryProbe`,
so scoring is verified without invoking `git`. `now` is injected for determinism; no signal
currently scores elapsed time. The real `GitRepository` is additionally exercised by on-disk
integration tests (`GitRepositoryIntegrationTests`) against a temporary repository.

## Coverage (Tests/AugurKitTests/RiskEngineTests.swift)

| Test | Asserts |
|------|---------|
| `testTrivialDocChangeProceeds` | A small docs edit yields `proceed`, risk `< 35`. |
| `testAuthChangeWithoutTestsEscalates` | Sensitive path + missing tests reach at least `review`. |
| `testTestAlongsideLowersRisk` | Touching a test file strictly lowers the source file's risk. |
| `testCalibrationConfidenceGrowsWithHistory` | Confidence `< 0.25` with thin history, `> 0.6` with deep history. |
| `testIncidentHistoryRaisesRiskOnlyWhenCalibrated` | Revert-prone file raises `incident`; calibration `> 0.5`. |
| `testNumstatParsing` | `git diff --numstat -z` (NUL-delimited) parsing, including binary (`-`) files. |
| `testLogParsing` | Single-pass log parsing and incident-subject detection. |
| `testDefaultThresholdsMatchOriginalBehavior` | `Thresholds.default` is `35`/`65`; `Verdict.from(riskScore:thresholds: .default)` equals the convenience overload at the `35`/`65` boundaries. |
| `testCustomThresholdsChangeVerdict` | Tightening thresholds escalates the verdict without changing the `riskScore`; `Assessment.thresholds` reflects the config. |
| `testThresholdsClampReviewBelowBlock` | `Thresholds` clamps `review` to be no greater than `block`. |
| `testCustomRulesMergeWithDefaults` | Custom rules merged onto the defaults match new paths while built-in categories still match. |
| `testCustomRuleRaisesRiskInEngine` | A merged custom rule raises a file's `sensitivity` signal and overall score. |
| `testCalibrationCacheRoundTrips` | A `CalibrationCache` encodes→decodes→rebuilds into a snapshot scoring identically to the live one. |
| `testCacheReportsBandAndConfidence` | The cache reports the correct calibration `band` and `confidence` for its volume. |

## Manual / dogfood

- `fledge run selfcheck` — run augur on its own working-tree changes.
- `augur check -C <repo> --range HEAD~1..HEAD` against a repo with real history.
