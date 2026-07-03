# Testing — Command-Line Interface

## Strategy

The CLI is exercised by `Tests/AugurCLITests`, which drives config loading and
argument validation directly (no subprocess). Config tests decode real TOML text
through `ConfigLoader`; validation tests parse argument vectors through
`ArgumentParser` and assert the resulting `ValidationError`s. The engine itself
is covered separately by `Tests/AugurKitTests` (see `change-confidence`).

## Coverage (Tests/AugurCLITests)

### ConfigTests.swift

| Test | Asserts |
|------|---------|
| `testTypoedSensitivityRulesAreRejected` | A misplaced `[[sensitivity.rules]]` is rejected, not silently ignored. |
| `testUnknownTopLevelKeyIsRejected` | An unknown root key fails closed. |
| `testUnknownNestedKeyIsRejectedWithSiblings` | A bad nested key names the valid siblings at that level. |
| `testUnknownKeyInsideRuleArrayIsRejectedWithIndex` | Unknown keys in `[[rules]]` report the array index. |
| `testSnakeAndCamelCaseKeysAreBothKnown` | `test_gap` / `testGap` / `test-gap` all resolve to the same schema entry. |
| `testValidConfigStillLoads` | A well-formed config decodes and builds an engine. |
| `testWrongTypeErrorNamesTheKeyPath` | A type mismatch reports the dotted key path, not a raw Swift error. |
| `testMissingRequiredKeyIsNamed` | A missing required key is named in the message. |
| `testAutoDetectedGarbageCoverageFallsBack` | An unparseable auto-detected report warns and falls back to the heuristic test-gap. |
| `testExplicitGarbageCoverageIsAHardError` | An unparseable explicit `--coverage` path is a hard error. |

### CommandValidationTests.swift

| Test | Asserts |
|------|---------|
| `testStagedAndRangeTogetherAreRejected` | `check` rejects `--range` with `--staged`. |
| `testGateRejectsConflictingScopeFlagsToo` | `gate` rejects the same conflicting scope. |
| `testSingleScopeFlagsStillParse` | A single scope flag parses cleanly. |
| `testInvalidGateThresholdFailsAtParseTimeWithGateUsage` | An invalid `--threshold` fails at parse time with gate's own usage. |
| `testValidGateThresholdParses` | A valid threshold parses. |
