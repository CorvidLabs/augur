---
hi: 1
families: [TUNE]
---

# Making it fit your repository

## Intent

Every codebase has its own idea of what is dangerous and its own noise to ignore, so augur should be adjustable without becoming a configuration project. Out of the box it must be useful with nothing configured, and any file you add should only ever refine that — leaving a section out has to mean exactly what it meant before you wrote the file. The adjustments people actually want are where the verdict lines sit, how much each reason counts, which paths in their own tree are sensitive, and which vendored or generated files should not be scored at all. Because this file decides how loudly a security signal fires, a mistake in it must fail loudly rather than quietly turn a rule off.

## Criteria

- **TUNE-1**  augur is useful with no configuration at all.
  - **TUNE-1.a**  A config file at the repository root is found without my pointing at it.
  - **TUNE-1.b**  Configuration only ever refines the defaults, so anything I leave out behaves exactly as before.
  - **TUNE-1.c**  I can ignore configuration entirely for one run.
  - **TUNE-1.d**  I can point augur at a config file that lives somewhere else.
  - **TUNE-1.e**  augur says which config it applied, so I am never guessing why a score moved.
- **TUNE-2**  I can move the line between proceed, review, and block to suit my repository.
  - **TUNE-2.a**  Moving the line changes the verdict and never the score behind it.
- **TUNE-3**  I can change how much each reason counts.
  - **TUNE-3.a**  Setting a reason's weight to zero takes it out of the picture.
- **TUNE-4**  I can teach augur which paths are sensitive in my own codebase.
  - **TUNE-4.a**  My rules sit alongside the built-in ones unless I say to replace them.
- **TUNE-5**  A typo in the config is a loud failure naming the key and what would have been valid there.
- **TUNE-6**  I can drop vendored, generated, and lockfile paths out of the assessment entirely.
  - **TUNE-6.a**  An excluded file appears in no score and in no reason.
  - **TUNE-6.b**  I am told what was excluded, even when that turns out to be everything.
  - **TUNE-6.c**  I can exclude something for one run without editing the config.
- **TUNE-7**  Exclusion patterns behave the way I expect from a shell, with a single star staying inside one path segment.
