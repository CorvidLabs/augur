---
module: change-confidence
version: 14
status: draft
files:
  - Sources/AugurKit/Models.swift
  - Sources/AugurKit/Git.swift
  - Sources/AugurKit/History.swift
  - Sources/AugurKit/Sensitivity.swift
  - Sources/AugurKit/RiskEngine.swift
  - Sources/AugurKit/Augur.swift
  - Sources/AugurKit/Reporter.swift
  - Sources/AugurKit/MarkdownReporter.swift
  - Sources/AugurKit/ANSI.swift
  - Sources/AugurKit/Coverage.swift
  - Sources/AugurKit/Sarif.swift
  - Sources/AugurKit/Glob.swift
  - Sources/AugurKit/CodeOwners.swift
db_tables: []
depends_on: []
---

# Change Confidence

## Purpose

Produce a deterministic, language-agnostic risk verdict for a set of changes
so that **humans** can triage where to spend review attention and **agents** can decide
whether to proceed or ask for human review. The core requires no API key and no LLM:
every signal is derived from `git` history and the filesystem. Optional AI explanations
are delegated to `fledge` and are purely additive.

The scoring has two layers:

1. A transparent **heuristic prior** (documented weights) that always applies.
2. A **history calibration** that scales the incident signal by how much the repository's
   own revert/hotfix record backs it, reported via `Calibration` so consumers know whether
   a score is "prior-only" or "history-backed".

## Public API

### Entry Point

| Export | Description |
|--------|-------------|
| `Augur.init(probe:engine:historyLimit:)` | Construct the facade over a `RepositoryProbe`. |
| `Augur.assess(scope:now:coverage:filter:codeOwners:)` | Probe the repository and return an `Assessment` for a `DiffScope`; an optional `CoverageReport` sharpens the test-gap signal per changed line, an optional `PathFilter` drops matching files before scoring, and an optional `CodeOwners` drives the `codeowners` signal. |
| `Assessment.jsonString()` | Render the assessment as stable, sorted-key JSON for agents. |
| `Assessment.jsonData()` | Same as `jsonString()` but returns `Data`. |
| `Assessment.empty(scope:)` | Construct the canonical successful result for a genuinely empty diff. |
| `Reporter.render(_:verbose:)` | Render an `Assessment` as plain human-readable terminal text. |
| `Reporter.render(_:verbose:color:)` | Render an `Assessment` as terminal text, optionally applying semantic ANSI color; `color: false` is byte-identical to the plain overload. |
| `MarkdownReporter.render(_:)` | Render an `Assessment` as deterministic GitHub-flavored markdown (verdict heading, confidence/calibration line, riskiest-first per-file table capped at `maxRows`, trailing `marker`) for PR comments / job summaries. |
| `MarkdownReporter.marker` | The hidden HTML-comment marker (`<!-- augur-report -->`) a CI job greps for to update a sticky PR comment in place. |
| `MarkdownReporter.maxRows` | The maximum number of file rows rendered before the remainder collapses into an "and N more" line (`25`). |

### Engine

| Export | Description |
|--------|-------------|
| `RiskEngine.init(weights:rules:thresholds:)` | Construct the engine with prior weights, sensitivity rules, and verdict thresholds. |
| `RiskEngine.assess(scope:changedFiles:history:now:coverage:codeOwners:excludedPaths:)` | Pure scoring over an explicit change surface and history, with an optional `CoverageReport` and `CodeOwners`; `excludedPaths` (already filtered out by the caller) is recorded on the `Assessment`. |
| `RiskEngine.Weights` | Documented prior weights for each signal including `codeowners` (sum to 1.0); `Codable`. |
| `RiskEngine.calibrationConfidence(totalCommits:incidentCommits:)` | Static calibration-confidence function (0...1). |

### Repository Access

| Export | Description |
|--------|-------------|
| `RepositoryProbe` | Protocol providing `changedFiles(in:)`, `recentCommits(limit:)`, and `headSHA()`. |
| `GitRepository` | `RepositoryProbe` backed by the `git` CLI; `validate()` confirms a work tree; `headSHA()` reports `HEAD`. |
| `HistorySnapshot.init(commits:)` | Derives churn, recency, ownership, coupling, and incidents from commits. |
| `HistorySnapshot.init(cache:)` | Rebuilds an equivalent snapshot from a `CalibrationCache` without re-walking `git log`. |
| `HistorySnapshot.makeCache(head:)` | Produces a serializable `CalibrationCache` pinned to a `HEAD` SHA. |
| `Augur.assess(scope:history:now:coverage:filter:codeOwners:)` | Assess using a pre-built snapshot (e.g. from a cache), skipping the log walk; optional `CoverageReport`, `PathFilter`, and `CodeOwners`. |
| `RepositoryProbe.addedLines(in:)` | Added (new-revision) line numbers per file in a scope; default `[:]`. `GitRepository` parses `git diff --unified=0`. |
| `Augur.calibrate()` | Walk history once and return a `CalibrationCache` pinned to the current `HEAD`. |
| `Augur.currentHead()` | The current `HEAD` SHA of the underlying repository. |
| `Augur.addedLines(in:)` | Added (new-revision) line numbers per changed file in a scope (passthrough to the probe), used to place SARIF result regions. |

### SARIF Output

| Export | Description |
|--------|-------------|
| `SarifReport.init(from:toolVersion:addedLinesByPath:)` | Project an `Assessment` into a SARIF 2.1.0 report: one `run`, one `result` per file, regioned on the first added line when known. |
| `SarifReport.jsonString()` / `jsonData()` | Stable, sorted-key SARIF JSON, mirroring the `Assessment` JSON renderers. |
| `SarifReport.Level.from(verdict:)` | Map a `Verdict` to a SARIF level (`block → error`, `review → warning`, `proceed → note`). |
| `SarifReport.schemaURL` / `sarifVersion` / `informationURI` / `ruleID` | The SARIF 2.1.0 schema URL, the format version (`"2.1.0"`), augur's project URL, and the single rule id (`augur/change-risk`). |
| `SarifReport` (+ `Run`, `Tool`, `Driver`, `ReportingDescriptor`, `Result`, `Level`, `Message`, `Location`, `PhysicalLocation`, `ArtifactLocation`, `Region`, `Properties`) | The Foundation-only `Codable` SARIF 2.1.0 subset augur emits. |

### Sensitivity

| Export | Description |
|--------|-------------|
| `SensitivityRule` | A path-fragment rule carrying an inherent risk weight. |
| `SensitivityRuleset.default` | Built-in rules: secrets, auth, crypto, payments, migration, infra, ci, dependencies. |
| `SensitivityRuleset.match(_:rules:)` | Highest-severity matching rule for a path, if any. |
| `TestHeuristics.isTestFile(_:)` | Language-agnostic test-file detection. |
| `DocumentationHeuristics.isDocumentationFile(_:)` | Documentation/prose detection (known doc extensions like `.md`/`.rst`/`.txt`, plus extension-less conventional basenames like `LICENSE`/`README`); keeps the test-gap signal from firing on files that cannot carry tests. |

### Path Exclusion

| Export | Description |
|--------|-------------|
| `GlobPattern` | A `Sendable` compiled glob matched against forward-slash paths: `*` (any chars except `/`), `**` (any chars incl `/`, matching zero or more segments), `?` (one char). Anchored to the whole path; `matches(_:)` reports a match. Foundation-only (compiled to `NSRegularExpression`); other regex metacharacters are escaped to match literally. |
| `PathFilter` | A `Sendable` wrapper over `[GlobPattern]`; `init(globs:)` / `init(patterns:)`, `excludes(_ path:)` (true when any pattern matches), and `isEmpty`. An empty filter excludes nothing. |

### CODEOWNERS

| Export | Description |
|--------|-------------|
| `CodeOwners` | A `Sendable` parsed `CODEOWNERS` file. `parse(_:)` reads the standard format (comments `#`, blank lines, each remaining line a pattern + zero or more owners); `owners(for path:)` returns the owners of a path with **last-match-wins** semantics (an owner-less rule unsets ownership; no match → `[]`). `isEmpty` and `rules` expose the parsed state. Patterns reuse `GlobPattern` (Foundation-only). |
| `CodeOwners.Rule` | One parsed rule: a compiled `pattern` (`GlobPattern`), its original `source` text, and `owners` (possibly empty). |
| `CodeOwners.standardLocations` | The standard repo-root locations (`.github/CODEOWNERS`, `CODEOWNERS`, `docs/CODEOWNERS`) in GitHub precedence order. |

### Coverage

| Export | Description |
|--------|-------------|
| `CoverageReport` | Parsed line coverage keyed by file; `query(path:changedLines:)` and `matchFile(diffPath:)`. |
| `CoverageReport.FileCoverage` | Per-file instrumented and covered line-number sets. |
| `CoverageQuery` | Result of a query: `covered`, `instrumented`, `fileMatched`, and `coveredFraction` (`nil` when nothing instrumented). |
| `CoverageParser.load(path:)` | Loads and parses an LCOV (`.info`), Cobertura/JaCoCo (`.xml`), or Go coverprofile (`.out`) file from disk; throws `fileNotFound` for a missing/unreadable file and `emptyReport` when the file parses to zero per-file records. |
| `CoverageParser.parse(contents:path:)` | Parses report text, auto-detecting the format. |
| `CoverageParser.parseLCOV(_:)` / `parseCobertura(_:)` / `parseJaCoCo(_:)` / `parseGoProfile(_:)` | Format-specific parsers (Foundation-only; Cobertura and JaCoCo via `XMLParser`, LCOV and Go coverprofile by line parsing). |
| `CoverageParser.detectFormat(path:contents:)` | Detects `.lcov` / `.cobertura` / `.jacoco` / `.go` by extension then content sniffing. |
| `CoverageParser.Format` (`lcov`, `cobertura`, `jacoco`, `go`) / `CoverageParser.ParseError` | The format enum and parse-failure errors (`fileNotFound`, `undetectableFormat`, `emptyReport`, `malformedXML`; `Equatable`). |

### Types & Enums

| Type | Description |
|------|-------------|
| `DiffScope` | `range(String)`, `staged`, or `workingTree` — the unit assessed. |
| `ChangedFile` | A touched file with added/deleted line counts, a binary flag, and `addedLines` (new-revision line numbers; empty when unknown). |
| `Commit` | A historical commit: hash, author email, timestamp, subject, files. |
| `Signal` | One deterministic risk contribution (`risk` 0...1, `weight`, `detail`). |
| `Verdict` | `proceed`, `review`, or `block`; `Comparable`; `from(riskScore:)` and `from(riskScore:thresholds:)`. |
| `Thresholds` | Configurable `review` / `block` cutoffs (0...100); `.default` is `35` / `65`; `review` is clamped `<= block`. |
| `FileAssessment` | Per-file `riskScore` (0...100), `confidence`, `verdict`, `verdict(thresholds:)`, and `signals`. |
| `Calibration` | `confidence` (0...1), `totalCommits`, `incidentCommits`, and a `band`. |
| `CalibrationCache` | `Codable` projection of a `HistorySnapshot` pinned to a `head` SHA; `confidence`, `band`, `jsonData()`, `decoded(from:)`. |
| `Assessment` | Versioned (`schemaVersion == 1`) overall `riskScore`, `verdict`, `calibration`, `thresholds`, per-file results, and `excludedPaths` (sorted paths dropped by a `PathFilter`; `excludedCount` is its size). |
| `AugurError` | `notARepository`, `git(command:status:stderr:)` (carries the child's captured stderr, rendered into the message when non-empty), `invalidRange(endpoint:)` for known-invalid range endpoints, `noChanges`. |

## Invariants

- `Signal.risk`, `FileAssessment.riskScore / 100`, and `Calibration.confidence` are clamped to `0...1` (scores to `0...100`).
- `FileAssessment.confidence == 100 - riskScore`; likewise for `Assessment`. This is a convenience inverse for reports, not an independent signal. `Assessment.jsonData()` encodes stored fields, so this computed value is not emitted as a top-level JSON key.
- `Verdict.from(riskScore:)` uses the default thresholds: `< 35 → proceed`, `< 65 → review`, otherwise `block`. `Verdict.from(riskScore:thresholds:)` applies configurable cutoffs (`>= block → block`, `>= review → review`, else `proceed`), and with `Thresholds.default` is identical to the convenience overload.
- `Thresholds` clamps `review` to be no greater than `block`, and both into `0...100`.
- A single file scoring `>= 80` forces the overall verdict to at least `block`.
- Thresholds change only the score→verdict mapping, never the `riskScore`; identical inputs under different thresholds yield identical scores.
- A `CalibrationCache` is a lossless projection of the snapshot facts the engine queries: a snapshot rebuilt via `HistorySnapshot(cache:)` produces an `Assessment` identical to one from the original commits. `topPartner` ties are broken by partner path so the projection is deterministic.
- The heuristic prior always contributes; the incident signal is multiplied by `Calibration.confidence`, so on a history-free repository the incident contribution is `0`.
- `RiskEngine.Weights` sum to `1.0` (including the `codeowners` weight); per-file score is the weight-normalized blend of its signals. When `codeowners` (`0.08`) was added, the seven prior weights were scaled by `1 - 0.08 = 0.92`, preserving their relative proportions while keeping the sum at `1.0`.
- The `codeowners` signal is **neutral** (`risk 0`, weight contributes nothing to the blend) when no `CodeOwners` is supplied (`nil`) — repos without a `CODEOWNERS` file are never penalized. When `CodeOwners` is supplied, a changed file with no declared owner scores `risk 0.6` ("no CODEOWNERS owner") and an owned file scores `risk 0` (detail lists the owners), so an unowned file scores strictly higher overall than the same change under no `CODEOWNERS`.
- `CodeOwners.owners(for:)` applies **last-match-wins**: among all rules whose pattern matches, the last in file order determines the owners; an owner-less rule unsets ownership; a path matching no rule is unowned (`[]`). `CodeOwners` parsing/matching is deterministic and Foundation-only (`GlobPattern`), with no `Date`/randomness.
- Assessment is deterministic: identical `(changedFiles, history, now, coverage, codeOwners)` yield identical output (byte-identical JSON). Coverage, glob, and CODEOWNERS parsing/matching use no `Date`/randomness.
- Successful JSON always uses the complete `Assessment` shape, including genuinely empty diffs.
  Pre-versioned payloads decode as schema v1 with default thresholds and exclusions.
- Coverage precedence in the test-gap signal: when a `CoverageReport` is supplied and the file is a non-test, non-binary code file with instrumented changed lines, `risk = 1 - covered/instrumented`; a code file entirely absent from the report is `0.7` ("not in coverage report"); when coverage cannot refine the file (no added lines known, or no changed line instrumented) the existing heuristic applies. With no coverage supplied, the heuristic test-gap behavior is unchanged.
- `CoverageQuery` counts only *instrumented* changed lines: a changed line the tool never instrumented contributes to neither `covered` nor `instrumented`, and `coveredFraction` is `nil` when `instrumented == 0`.
- Coverage path matching is by normalized longest-suffix at component boundaries; exact (normalized) matches win, ties break by shorter then lexicographically-smaller reported path. Diff/coverage prefix differences are tolerated; identical suffixes across distinct files are ambiguous (documented limitation).
- `Augur.assess` is pure with respect to an injected `now`, enabling reproducible tests. No current signal scores elapsed time, so `now` does not affect the verdict; it is reserved for a future time-based signal and exposed via `HistorySnapshot.daysSinceTouched(_:now:)`.
- `GitRepository` reads changed paths verbatim: `changedFiles(in:)` uses `git diff --numstat -z` (NUL-delimited, unquoted), and every git invocation runs with `-c core.quotepath=false`. A renamed/copied file resolves to its NEW path (not git's synthetic `{old => new}` brace string), with a pure rename (0 added / 0 deleted) yielding zero churn. Non-ASCII paths (e.g. `café.go`) round-trip as verbatim UTF-8, so CODEOWNERS, `--exclude`, coverage matching, and the SARIF `artifactLocation.uri` all see the real path. These guarantees are covered by on-disk integration tests against a temporary repository.
- `GitRepository` rejects GitHub's all-zero branch-creation sentinel SHA (`0000000000000000000000000000000000000000`) when it appears as the left or right endpoint of a `DiffScope.range` (`..` or `...`) before invoking `git diff`. The thrown `AugurError.invalidRange(endpoint:)` explains that the value is a branch-creation sentinel, not a commit, and suggests an explicit base ref such as `origin/main..HEAD` or `$(git merge-base origin/main HEAD)..HEAD`; Augur never silently rewrites the range.
- A `workingTree` assessment includes **untracked** files (`git ls-files --others --exclude-standard`, honoring `.gitignore`): each is reported as a fully-added `ChangedFile` (`linesAdded` = its on-disk line count, `linesDeleted == 0`, `addedLines` spanning every line; a blob with a NUL byte in its first 8000 bytes is binary with no line data), so a brand-new file is never invisible to a risk gate. `staged` and `range` scopes remain exact diffs and never gain untracked files; a tracked path wins on collision. `GitRepository.addedLines(in:)` covers untracked files in the `workingTree` scope too, so coverage scoring and SARIF regions line up.
- A failing git invocation surfaces the child's captured stderr: `AugurError.git(command:status:stderr:)` carries it, and the rendered message appends the trimmed stderr (e.g. git's `fatal: ambiguous argument ...`) when non-empty.
- The test-gap signal never fires on prose: a changed file matching `DocumentationHeuristics.isDocumentationFile` (and not a test file) scores test-gap `risk 0` ("documentation, not unit-testable") regardless of coverage, so a docs-only change is not penalized for lacking tests. Code files keep the existing heuristic/coverage behavior.
- Path exclusion happens **before** scoring: a changed file whose path matches any `PathFilter` pattern is removed from the change surface, so it appears in neither `Assessment.files` nor any signal, and is recorded in `Assessment.excludedPaths` (sorted). A `nil` or empty filter excludes nothing and yields an `Assessment` identical to passing no filter (`excludedPaths == []`). Exclusion is deterministic (`GlobPattern` matching uses no `Date`/randomness) and `GlobPattern`/`PathFilter` are Foundation-only (no third-party dependency). When the scope has changed files but *every* one is excluded, `assess` does **not** throw: it returns a normal `Assessment` with empty `files`, the populated `excludedPaths`, verdict `proceed`, and `riskScore == 0`, so the exclusions stay visible in human and JSON output. `assess` throws `AugurError.noChanges` only when the scope had no changed files at all (before filtering).
- `GlobPattern` is whole-path anchored: `*` matches within a single path segment (never `/`), `**` matches across segments and also zero segments (so `vendor/**` matches the bare `vendor`), and `?` matches exactly one character. Paths are normalized (leading `./`, repeated and trailing slashes) before matching.
- SARIF output is a lossless-enough projection of an `Assessment`: `SarifReport(from:)` emits exactly one `run` with one `result` per assessed file (in assessment order), `version == "2.1.0"`, and one reporting descriptor (`augur/change-risk`). Each result's `level` is `SarifReport.Level.from(verdict:)` under the assessment's thresholds — `block → error`, `review → warning`, `proceed → note` — and carries `riskScore`/`confidence`/`verdict` in `result.properties`. A result's `region.startLine` is the file's smallest added line when `addedLines` is non-empty, otherwise the region is omitted.
- SARIF JSON is deterministic (sorted keys, no `Date`/randomness) and round-trips: `SarifReport.jsonData()` decodes back to an equal `SarifReport`. SARIF lives in `AugurKit` and uses Foundation `Codable` only — no third-party dependency.

## Behavioral Examples

- A 3-line docs edit, no sensitive paths, tests untouched → `proceed` (risk `< 35`); its test-gap signal is `0` ("documentation, not unit-testable"), so a docs-only change can score near `0` instead of being penalized for carrying no tests. `isDocumentationFile` accepts `README.md`, `docs/guide.rst`, `notes.TXT`, `LICENSE`, and `CHANGELOG`, but not `src/service.swift`, `changelog.swift`, or `Makefile`.
- `touch src/new.swift` (never `git add`ed) then a `workingTree` assessment reports `src/new.swift` as a changed file with `linesAdded` equal to its line count and `addedLines == [1...N]`; the same file is absent from `staged` and `range` assessments, and a `.gitignore`d file is absent everywhere.
- A 160-line edit to `src/auth/token.swift` with no test in the changeset → at least `review`; the `sensitivity` and `test-gap` signals are non-zero.
- The same source change *with* a sibling test file in the changeset scores strictly lower than without it.
- A file repeatedly implicated in `Revert "..."` commits, in a repo with deep history, raises the `incident` signal and reports `calibration.confidence > 0.5`.
- `calibrationConfidence(totalCommits: 10, incidentCommits: 0) < 0.25`; `calibrationConfidence(totalCommits: 400, incidentCommits: 40) > 0.6`.
- `GitRepository.changedFiles(in: .range("0000000000000000000000000000000000000000..HEAD"))` throws `AugurError.invalidRange(endpoint:)` before calling `git diff`, and its message tells the user to choose an explicit base ref or merge-base instead of treating the sentinel as a commit.
- A change that scores `proceed` under the default thresholds becomes `block` under `Thresholds(review: 1, block: 2)` while keeping the same `riskScore`.
- A custom `SensitivityRule` merged onto `SensitivityRuleset.default` makes a previously-unflagged path (e.g. `pkg/internal/api.swift`) match, raising its `sensitivity` signal and overall score, while built-in categories still match.
- Encoding a `HistorySnapshot` to a `CalibrationCache`, JSON round-tripping it, and rebuilding via `HistorySnapshot(cache:)` yields an `Assessment` equal to the live one.
- A code file whose changed lines (e.g. `10,11,12`) are all covered scores `test-gap` risk `0` ("3/3 changed lines covered (100%)"); the same file with those lines uncovered scores risk `1` ("0/3 ..."), and its overall `riskScore` is strictly higher than the covered case.
- A changed code file absent from the supplied coverage report scores `test-gap` risk `0.7` ("not in coverage report").
- Parsing LCOV `SF:`/`DA:` records and Cobertura `<class filename><lines><line number hits>` yields, per file, the instrumented and covered line-number sets; `query(path:changedLines:)` restricts counts to instrumented changed lines.
- Parsing JaCoCo `<report><package name><sourcefile name><line nr mi ci>` yields, per file, instrumented lines (those with a `line` element) and covered lines (`ci > 0`); the reported path is `package@name` + `/` + `sourcefile@name` (e.g. `com/foo` + `Bar.kt` → `com/foo/Bar.kt`, an empty package gives the bare sourcefile name), reconciled with diff paths by the existing suffix matching.
- Parsing a Go coverprofile (`mode:` header then `path:startLine.col,endLine.col numStmts count` blocks) instruments every line in `startLine...endLine` and covers a line when *any* block over it has `count > 0`; accumulated per file path.
- `detectFormat` recognizes JaCoCo XML (a `<report>`+`<sourcefile>` pairing or a `jacoco` marker, even with an `.xml` extension) and a Go coverprofile (first non-empty line begins `mode:`, or an `.out` extension), while LCOV (`.info`) and Cobertura (`.xml`/`<coverage`) detection is unchanged.
- A coverage path `/build/checkout/Sources/App/Service.swift` matches the diff path `Sources/App/Service.swift` by longest suffix; a path sharing no trailing component does not match.
- A change touching `src/service.swift`, `vendor/lib/huge.swift`, and `Sources/App/Model.generated.swift`, assessed with `PathFilter(globs: ["vendor/**", "**/*.generated.swift"])`, scores only `src/service.swift` (the others appear in neither `files` nor any signal) and reports `excludedPaths == ["Sources/App/Model.generated.swift", "vendor/lib/huge.swift"]`. Excluding *all* changed files (e.g. a vendored-only change under `vendor/**`) returns an `Assessment` with empty `files`, verdict `proceed`, `riskScore == 0`, and `excludedPaths` listing every excluded path (a genuinely empty diff, with no changed files at all, still throws `AugurError.noChanges`). `GlobPattern("vendor/**")` matches `vendor`, `vendor/a`, and `vendor/a/b/c.swift` but not `src/vendor/x`, and (because every `**` is anchored at a `/` boundary) not the prefix-sharing siblings `vendors/x`, `vendorize.go`, or `vendor-old/y`; `GlobPattern("**/foo")` matches `foo` and `a/b/foo` but not `barfoo`; `GlobPattern("src/*.swift")` matches `src/x.swift` but not `src/sub/x.swift`; `GlobPattern("file?.txt")` matches `file1.txt` but not `file.txt` or `file12.txt`.
- With no `CodeOwners` supplied, a changed file's `codeowners` signal is `risk 0` ("no CODEOWNERS file"). Parsing the `CODEOWNERS` body `* @global` then `/src/ @src-team` and assessing `src/service.swift` yields a `codeowners` signal of `risk 0` ("owned by @src-team"); assessing `lib/service.swift` (matched only by `*`) is owned by `@global`; a body of just `/docs/ @docs-team` leaves `src/service.swift` unowned (`risk 0.6`, "no CODEOWNERS owner") and that file scores strictly higher overall than the same change with no `CODEOWNERS`. `CodeOwners.parse` with `* @global` then `/generated/` (no owners) reports `generated/code.swift` as unowned (the empty rule unsets the catch-all), while `*.swift @swift` owns `Sources/App/Deep/File.swift` at any depth.
- An assessment with a `block`, a `review`, and a `proceed` file projects to a `SarifReport` with `version == "2.1.0"`, three results whose `level`s are `error`, `warning`, and `note` respectively, each citing rule `augur/change-risk`; a file with added lines `[42, 7, 99]` gets `region.startLine == 7`, a file with no added lines gets no region, and the SARIF JSON decodes back to an equal report.
- `MarkdownReporter.render` of a `review` assessment (risk `58`) over three files emits a heading line `### augur: ⚠️ REVIEW - risk 58/100`, a `Confidence 42/100 - calibration ...` line, a `| File | Risk | Verdict | Top signal |` table whose rows are riskiest-first (each row's "Top signal" is the file's highest weight*risk signal detail, or `-` when none contributes), and a trailing `<!-- augur-report -->` marker on its own line; rendering is deterministic (byte-identical across runs) and contains no em-dash. When more than `MarkdownReporter.maxRows` (`25`) files are present, only the riskiest `maxRows` rows render and an "and N more files." line follows; a `|` inside a path or detail is escaped to `\|` so the table stays well-formed.

## Error Cases

- `AugurError.notARepository(path)` — `GitRepository.validate()` finds no git work tree at `path`.
- `AugurError.git(command:status:stderr:)` — an underlying `git` invocation exits non-zero; `stderr` carries the child's captured diagnostic and is appended to the rendered message when non-empty.
- `AugurError.invalidRange(endpoint:)` — a `DiffScope.range` contains GitHub's all-zero branch-creation sentinel as an endpoint; this is rejected before `git diff` and rendered as an actionable invalid-range diagnostic.
- `CoverageParser.ParseError.fileNotFound(path)` — `load(path:)` on a missing/unreadable file (distinct from `undetectableFormat`, which means the contents could not be classified). `ParseError.emptyReport(path)` — the file parsed to zero per-file records (e.g. garbage with a coverage extension); a report must never "load" silently with nothing in it.
- `AugurError.noChanges`: the requested scope contains no changed files at all (before any `PathFilter` is applied); the CLI treats this as a clean `proceed`. A scope that does have changed files but excludes every one does not throw: it yields a `proceed` `Assessment` with empty `files` and populated `excludedPaths`.

## Dependencies

- `git` available on `PATH` (the only runtime requirement of the core).
- `swift-argument-parser` (CLI target only; `AugurKit` has no external dependencies).
- `TOMLDecoder` (CLI target only) to parse `.augur.toml`; `AugurKit` stays dependency-free.
- `fledge` (optional, `augur explain` only) for AI explanations.

## Change Log

- v13: Clear diagnostics for GitHub branch-creation push ranges. `GitRepository` now recognizes the all-zero GitHub `before` sentinel SHA when it appears as a range endpoint and throws `AugurError.invalidRange(endpoint:)` before invoking either `git diff --numstat -z` or `git diff --unified=0`. The rendered message explains that the sentinel is not a commit, suggests `origin/main..HEAD` or `$(git merge-base origin/main HEAD)..HEAD`, and Augur does not silently reinterpret the range. `check` and `gate` share this diagnostic through the existing probe path. `AugurKit` remains free of third-party dependencies.
- v12: Hands-on hardening: no silent under-reporting, no silent fail-open. **Untracked files are assessed**: `GitRepository.changedFiles(in: .workingTree)` appends `git ls-files --others --exclude-standard` results as fully-added files (on-disk line count, `addedLines` spanning every line, NUL-sniffed binary flag); `staged`/`range` scopes are unchanged, and `addedLines(in:)` covers untracked files too. **Git stderr surfaces**: `AugurError.git` gains a `stderr` associated value (breaking enum-case change), captured by `ProcessRunner` and appended to the rendered message, so a bad range reports git's own `fatal: ...` instead of a bare exit code. **Coverage loading fails loudly**: `CoverageParser.ParseError` gains `fileNotFound` (a missing file no longer reads as "could not detect format") and `emptyReport` (zero parsed records is an error, not a silent no-op load); `ParseError` is now `Equatable`. **Docs don't owe tests**: new `DocumentationHeuristics.isDocumentationFile(_:)`, and the test-gap signal scores `0` ("documentation, not unit-testable") for prose files, so docs-only changes can score near zero. Reporter/markdown calibration lines and churn/diff-shape details now pluralize correctly ("1 incident", "1 line touched"). CLI (no `AugurKit` surface): `.augur.toml` parsing rejects unknown keys with the offending key path and valid siblings (a typo'd `[[sensitivity.rules]]` is a hard error instead of failing open), TOML decode errors render as human-readable key-path messages, `--staged` + `--range` is a usage error (exit 64), an invalid `gate --threshold` reports gate's own usage, and an unusable auto-detected coverage file warns and falls back instead of being silently "loaded". `AugurKit` remains free of third-party dependencies.
- v11: Exclusion transparency when the filter drops every changed file. `Augur.assess(...)` (both overloads) no longer throws `AugurError.noChanges` when the scope had changed files but a `PathFilter` excluded all of them; instead it returns a normal `Assessment` with empty `files`, the populated `excludedPaths`, verdict `proceed`, and `riskScore == 0`, so a risk tool never silently hides what it dropped. `noChanges` is now thrown only for a genuinely empty scope (no changed files before filtering). The human reporter and markdown report add a "nothing left to assess" note in this all-excluded case, and JSON continues to surface `excludedPaths`. No public type signatures changed. `Glob.translate` anchors the compiled regex with `\A` / `\z` (instead of `^` / `$`) so a glob cannot match across a stray trailing newline. `AugurKit` remains free of third-party dependencies.
- v14: Versioned, uniform assessment JSON. `Assessment.schemaVersion` is emitted as `1`, while
  custom decoding accepts legacy payloads without it and supplies default thresholds/exclusions.
  `Assessment.empty(scope:)` centralizes the canonical zero-risk result. The CLI no longer prints
  a reduced hand-written object for `check --json` on an empty diff; every successful JSON result
  now has the same complete shape. Scoring and verdict semantics are unchanged.
- v10: Correct git-layer path handling for renames and non-ASCII filenames. `GitRepository.changedFiles(in:)` now reads `git diff --numstat -z` (NUL-delimited records that disable path quoting and split a rename/copy into `added\tdeleted\t\0<oldpath>\0<newpath>`), and `parseNumstat` resolves a rename to its NEW path rather than git's synthetic `{old => new}` brace string (a pure rename has zero churn). Every git invocation now runs with `-c core.quotepath=false`, so non-ASCII paths round-trip as verbatim UTF-8 instead of octal-escaped, fixing CODEOWNERS / `--exclude` / coverage matching and the `diff --unified=0` and `log --name-only` paths. These behaviors are proven by on-disk integration tests. No public type signatures changed; the recency over-claim in docs was corrected (no signal scores elapsed time; `now` is reserved). CLI quick wins: `--sarif` help lists all three exclusive formats, and custom `[weights]` that do not sum to ~1.0 emit a non-fatal stderr warning.
- v9: Native markdown report for PR-level visibility (`MarkdownReporter.swift`, Foundation-only). New `Sendable` `MarkdownReporter` with `static func render(_:) -> String` producing deterministic GitHub-flavored markdown: a verdict heading (`### augur: <emoji> <VERDICT> - risk <N>/100`, emoji `proceed → ✅`, `review → ⚠️`, `block → ⛔`, no em-dashes), a `Confidence <N>/100 - calibration <band> (<incidents> incidents / <commits> commits).` line, a `| File | Risk | Verdict | Top signal |` table riskiest-first (ties broken by path; "Top signal" is the file's highest weight*risk signal detail, `-` when none), capped at `maxRows` (`25`) rows with an "and N more files." overflow line, and a trailing `marker` (`<!-- augur-report -->`) line a CI job greps to update a sticky PR comment. Table cells escape `\`, `|`, and newlines. CLI: `check` gains `--markdown` (prints the report to stdout), mutually exclusive with `--json` and `--sarif`. `AugurKit` remains free of third-party dependencies.
- v8: Colorful terminal output for the human reporter (`ANSI.swift`, Foundation-only, internal). New internal `ANSI` (escape codes / `Attribute` / `Style`), `Palette` (semantic verdict/level/label styles), and `Colorizer` (`enabled` gate; a no-op when disabled). `Reporter` gains a `render(_:verbose:color:)` overload; the existing `render(_:verbose:)` is preserved and is exactly `render(_:verbose:color:false)`, which is byte-identical to prior plain output. When `color: true`, the verdict badge/word is tinted (`proceed → green`, `review → yellow`, `block → bold red`), the risk meter uses gradient block glyphs (`█`/`░`) colored by level, headers are bold, secondary/signal detail is dim, file paths are cyan, per-file rows are tinted by that file's verdict, and confidence/calibration are cyan. CLI: `check` gains `--color <auto|always|never>` (default `auto`); `auto` enables color only when stdout is a TTY and `NO_COLOR` is unset (https://no-color.org), so piped / `--json` / `--sarif` output stays plain. `AugurKit` remains free of third-party dependencies.
- v7: CODEOWNERS-aware ownership signal (`CodeOwners.swift`, Foundation-only, reusing `GlobPattern`). New `Sendable` `CodeOwners` (with `CodeOwners.Rule`): `parse(_:)` reads the standard `CODEOWNERS` format (comments, blanks, `<pattern> @owner...`), translating gitignore-like patterns to `GlobPattern` syntax (`*` → `**`, leading `/` anchors, trailing `/` → `dir/**`, a bare name matches at any depth via `**/name`); `owners(for path:)` returns a path's owners with **last-match-wins** semantics (owner-less rule unsets; no match → `[]`). `standardLocations` lists `.github/CODEOWNERS`, `CODEOWNERS`, `docs/CODEOWNERS`. A new `codeowners` signal in `RiskEngine.assessFile`: neutral (`0`) when no `CodeOwners` is supplied, `0.6` ("no CODEOWNERS owner") for an unowned changed file, `0` (detail lists owners) when owned. `RiskEngine.Weights` gains `codeowners` (`0.08`); the seven prior weights are scaled by `0.92` so the blend still sums to `1.0` with unchanged relative proportions. Both `Augur.assess(...)` overloads and `RiskEngine.assess(...)` gain an optional `codeOwners:` parameter (default `nil`). CLI: `check`/`gate` auto-discover a `CODEOWNERS` file at the standard locations and accept `--no-codeowners` to disable; the owner appears in the signal detail (human + JSON); `.augur.toml [weights] codeowners` is parseable in the CLI layer. `AugurKit` remains free of third-party dependencies.
- v6: Path exclusions for generated/vendored files (`Glob.swift`, Foundation-only). New `Sendable` `GlobPattern` (a whole-path-anchored glob supporting `*` = any chars except `/`, `**` = any chars incl `/` and zero or more segments, `?` = one char; lowered to `NSRegularExpression` with all other metacharacters escaped) and `PathFilter` (a `[GlobPattern]` wrapper with `excludes(_:)` / `isEmpty`). `Augur.assess(...)` gains an optional `filter:` parameter on both overloads (default `nil`); matching files are dropped **before** scoring and recorded in the new `Assessment.excludedPaths` (sorted; `excludedCount` is its size). `RiskEngine.assess(...)` gains `excludedPaths:` (default `[]`) to carry the report through. Excluding all changed files throws `AugurError.noChanges`. CLI: `.augur.toml` gains `[exclude] paths = [...]` (parsed in the CLI layer); `check`/`gate` gain repeatable `--exclude <glob>` (added to configured excludes) and `--no-exclude` (ignore configured excludes; CLI globs still apply). The human reporter prints `excluded: N files` when any were excluded; JSON includes `excludedPaths`. `AugurKit` remains free of third-party dependencies.
- v5: Two more coverage formats ingested by the existing `CoverageParser`, keeping `AugurKit` Foundation-only. **JaCoCo XML** (Kotlin/Java) via `parseJaCoCo(_:)`: a `<line nr ...>` under `<package name><sourcefile name>` is instrumented, covered when `ci` (covered instructions) > 0; the reported path is `package@name` + `/` + `sourcefile@name`, reconciled by the existing suffix matching. **Go coverprofile** (`go test -coverprofile`) via `parseGoProfile(_:)`: a `mode:` header then `path:start.col,end.col numStmts count` blocks; each block instruments lines `start...end` and covers them when `count > 0` (a line is covered if any covering block has `count > 0`). `CoverageParser.Format` gains `jacoco` and `go`; `detectFormat` recognizes JaCoCo (`<report>`+`<sourcefile>` markers / `jacoco`) and Go (`mode:` first line / `.out` extension), with LCOV and Cobertura detection unchanged. `--coverage <path>` now accepts all four formats; auto-detection at the repo root also looks for `jacoco.xml`, `cover.out`, and `coverage.out` (first found wins, logged to stderr). The `CoverageReport` query API and the engine's consumption are unchanged. `AugurKit` remains free of third-party dependencies.
- v4: SARIF 2.1.0 output (`Sarif.swift`). New Foundation-only `Codable` `SarifReport` model (a minimal valid SARIF 2.1.0 subset) with `init(from:toolVersion:addedLinesByPath:)` projecting an `Assessment` into one `run` carrying one `result` per file under a single `augur/change-risk` reporting descriptor; result `level` is mapped from each file's verdict (`block → error`, `review → warning`, `proceed → note`), `region.startLine` is the file's first added line when known, and `riskScore`/`confidence`/`verdict` go in `result.properties`. `SarifReport.jsonString()`/`jsonData()` mirror the `Assessment` renderers (sorted-key, deterministic). `Augur.addedLines(in:)` is exposed as a probe passthrough so the CLI can place regions. CLI adds `--sarif` and `--sarif-out <path>` to `check` (mutually exclusive with `--json`; `--sarif-out` implies `--sarif`). `AugurKit` remains free of third-party dependencies.
- v3: Per-line coverage ingestion (`Coverage.swift`). New `CoverageReport` / `CoverageReport.FileCoverage` / `CoverageQuery` types and a Foundation-only `CoverageParser` (LCOV + Cobertura XML via `XMLParser`, with format auto-detection and `load(path:)`). `ChangedFile` gains `addedLines` (default empty, back-compatible). `RepositoryProbe` gains `addedLines(in:)` (default `[:]`); `GitRepository` parses `git diff --unified=0` hunk headers to populate it. Optional `coverage:` parameter threaded through `RiskEngine.assess(...)` and both `Augur.assess(...)` overloads (default `nil`); when supplied, the test-gap signal becomes `1 - covered/instrumented` over a file's instrumented changed lines (absent file → `0.7`), otherwise the original heuristic is unchanged. CLI adds `--coverage <path>` and `--no-coverage` to `check`/`gate`, with auto-detection of `lcov.info` / `coverage.xml` at the repo root. A composite `action.yml` ("augur gate") builds augur from its own checkout and gates on self-hosted macOS. `AugurKit` remains free of third-party dependencies.
- v2: Configurable verdict thresholds via `Thresholds` (engine + `Verdict.from(riskScore:thresholds:)`), threaded through `RiskEngine.init(weights:rules:thresholds:)` and surfaced on `Assessment.thresholds`. `Weights` is now `Codable`. Added `CalibrationCache` (a `Codable` projection of `HistorySnapshot`) with `HistorySnapshot.init(cache:)` / `makeCache(head:)`, `Augur.calibrate()` / `assess(scope:history:now:)` / `currentHead()`, and `RepositoryProbe.headSHA()`. `topPartner` now breaks ties deterministically by partner path. CLI adds `.augur.toml` config (parsed in the CLI layer only), the `calibrate` command, `check --cached`, and `--config` / `--no-config`. `AugurKit` remains free of third-party dependencies.
- v1: Initial change-confidence engine — deterministic signals (sensitivity, test-gap, churn, coupling, diff-shape, ownership, incident), two-layer prior + history calibration, JSON and human reporters, `check`/`gate`/`explain` CLI.
