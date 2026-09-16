---
hi: 1
families: [COVERAGE]
---

# Sharpening the test gap

## Intent

Guessing whether a change is tested by looking for a test file in the diff is crude, and augur should do better the moment a project can tell it more. Handed a coverage report, the testing reason should become a fact about the lines this change actually added rather than a hunch about the changeset. This should cost nobody any setup: the report a toolchain already drops at the repo root should just be found and used. Where the data cannot answer honestly, augur should fall back to the guess and say so rather than invent a number, and a report it was explicitly told to use but cannot must fail rather than be ignored.

## Criteria

- **COVERAGE-1**  I can hand augur a coverage report and have the testing reason become exact instead of a guess.
  - **COVERAGE-1.a**  A file whose changed lines are all covered stops counting as a testing risk.
  - **COVERAGE-1.b**  A file the coverage report never mentions is treated as untested.
  - **COVERAGE-1.c**  Only the lines the change added are scored, not the ones around them.
  - **COVERAGE-1.d**  When the report has nothing to say about the lines I changed, augur falls back to its plain guess rather than inventing a number.
- **COVERAGE-2**  The coverage formats my toolchain already produces are understood without my converting anything.
- **COVERAGE-3**  A report sitting at the repository root is picked up without my naming it.
  - **COVERAGE-3.a**  A picked-up report that turns out to be unusable warns and steps aside rather than stopping the run.
  - **COVERAGE-3.b**  I can turn that automatic pickup off when I do not want it.
- **COVERAGE-4**  A coverage file I named myself that cannot be used is a hard error.
  - **COVERAGE-4.a**  A report that parses to nothing is rejected rather than loading as empty.
- **COVERAGE-5**  Coverage paths carrying a build machine's prefix still line up with my repository's paths.
  - **COVERAGE-5.a**  When two files could answer to the same coverage entry, the tie is broken the same way every time.
