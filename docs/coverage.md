# Coverage-aware test-gap

By default the **test-gap** signal is a coarse heuristic: did the changeset touch
any test file? Supply a line-coverage report and it becomes precise. It scores
the fraction of the change's *added* lines that are actually covered.

```sh
augur check --coverage lcov.info      # LCOV
augur check --coverage coverage.xml   # Cobertura XML
augur check --coverage jacoco.xml     # JaCoCo XML (Kotlin/Java)
augur check --coverage cover.out      # Go coverprofile
augur check --no-coverage             # disable auto-detection
```

All four parsers live in `AugurKit` and use **Foundation only** (no third-party
dependency): Cobertura and JaCoCo via `XMLParser`, LCOV and Go coverprofiles by
line parsing.

## Supported formats

| Format | Typical name | How a line is instrumented / covered |
|--------|--------------|--------------------------------------|
| **LCOV** | `lcov.info` | `DA:<line>,<hits>`. Covered when `hits > 0`. |
| **Cobertura** | `coverage.xml` | `<line number="N" hits="H"/>`. Covered when `hits > 0`. |
| **JaCoCo** | `jacoco.xml` | `<line nr="N" ci="C"/>` under `<package><sourcefile>`. Covered when `ci` (covered instructions) `> 0`; reported path is `package@name`/`sourcefile@name`. |
| **Go** | `cover.out` | `path:start.col,end.col stmts count` blocks; every line in `start…end`. Covered when *any* covering block has `count > 0`. |

## Auto-detection

When `--coverage` is absent (and `--no-coverage` is not set), `augur` looks for a
report at the repo root, trying these names in order and using the **first** that
exists (logged to stderr):

```
lcov.info → coverage.xml → jacoco.xml → cover.out → coverage.out
```

The format is detected by extension first (`.info` → LCOV, `.out` → Go, `.xml` →
Cobertura/JaCoCo), then by content sniffing: JaCoCo is distinguished from
Cobertura by its `<report>`/`<sourcefile>` markers; a Go profile by its leading
`mode:` line.

## Scoring behavior

Per non-test, non-binary **code** file:

- **Has instrumented changed lines** → `risk = 1 − (covered ÷ instrumented)`,
  with a detail like `2/3 changed lines covered (67%)`.
- **Entirely absent from the report** → high risk (`0.7`, "not in coverage
  report").
- **No changed line was instrumented** (e.g. only comments / blank lines changed),
  or no per-line data is available → falls back to the heuristic test-gap.
- **No coverage supplied at all** → the original heuristic, unchanged.

Only *instrumented* changed lines count: a changed line the tool never
instrumented (a comment, a blank line) contributes to neither the numerator nor
the denominator.

## Path-matching caveats

Coverage tools and git diffs often disagree on a leading path prefix
(`src/a.swift` vs `/build/checkout/src/a.swift`). `augur` reconciles them by
**normalized longest-suffix matching at component boundaries**: the report file
sharing the most trailing path components with the diff path wins. An exact
(normalized) match always wins.

**Limitation:** when two report files share an identical suffix (e.g.
`a/util.swift` and `b/util.swift` both matched against a diff path `util.swift`),
the match is ambiguous. It is resolved deterministically (shorter reported path,
then lexicographically smallest), but it may not be the file you intended.

**Recommendation:** emit coverage with **repo-relative paths** where possible, so
suffix matching is unambiguous.

## Malformed input

The parsers degrade gracefully: malformed or empty LCOV/Cobertura/JaCoCo/Go
inputs yield a sensible empty (or partial) report rather than crashing. An input
whose format cannot be detected at all throws `CoverageParser.ParseError.undetectableFormat`.
