---
title: "Quickstart"
description: "Install augur and get your first risk verdict in under a minute."
section: "Getting started"
order: 1
---

Get `augur` running on your project in under a minute. `augur` needs no API key,
no LLM, and no configuration to start, just Swift 6 and `git` on `PATH`. It is
macOS-only.

---

## 1. Install

`augur` is a Swift package. Build the release binary and drop it on your `PATH`:

```sh
swift build -c release
install -m 0755 .build/release/augur /usr/local/bin/augur
# or, with fledge:
fledge run install
```

Verify it:

```sh
augur check --help
```

### Try it instantly (no setup)

Every script in [`examples/`](https://github.com/CorvidLabs/augur/tree/main/examples)
builds the binary and runs it against a throwaway `/tmp` repo, so you get a real verdict
in seconds:

```sh
bash examples/01-check.sh
```

---

## 2. Get a verdict

`augur` is **range-first**. With no scope flag it assesses the working tree
(staged + unstaged) against `HEAD`:

```sh
augur check                         # working-tree changes
augur check --range main..HEAD      # an explicit git range
augur check --staged                # staged changes only (pre-commit)
augur check -v                      # show every contributing signal
```

A typical assessment:

```
$ augur check --range main..HEAD

augur · main..HEAD

  verdict     [!] REVIEW
  risk        [##########          ]  50/100
  confidence  50/100
  calibration history-backed (156 incidents / 500 commits)

  files (1), riskiest first:
    !    50  src/auth/token.swift
          · sensitivity: matches sensitive category 'auth'

  → an agent should request human review before merging
```

On a real terminal this is **colored**: the verdict is tinted by level
(<span style="color:var(--proceed)">green&nbsp;proceed</span> ·
<span style="color:var(--review)">amber&nbsp;review</span> ·
<span style="color:var(--block)">red&nbsp;block</span>), the risk meter renders as a
<span style="color:var(--review)">█</span><span style="color:var(--text-dim)">░</span>
gauge tinted by the same scale, file paths are
<span style="color:var(--term-cyan)">cyan</span>, and secondary detail is dimmed.
Color is **TTY-aware**: `augur` emits plain text (exactly as shown above) whenever
stdout is not a terminal, so piped, redirected, `--json`, and `--sarif` output
stays clean and scriptable. Control it with `--color auto|always|never` (default
`auto`), and `augur` honors the [`NO_COLOR`](https://no-color.org) convention.

`check` always exits `0`: it reports, it does not gate.

---

## 3. Gate in CI or an agent loop

`augur gate` exits **non-zero** when the verdict meets or exceeds a threshold, so
a pipeline fails or an agent escalates instead of merging blind:

```sh
augur gate --threshold review        # exit 1 if verdict >= review
augur gate --range origin/main..HEAD --threshold block
```

| Exit code | Meaning |
|----------:|---------|
| `0` | Verdict below the threshold (or no changes). |
| `1` | Verdict met or exceeded the threshold. |
| `2` | Usage / validation error. |

### For agents

```sh
verdict=$(augur check --range main..HEAD --json | jq -r .verdict)
[ "$verdict" = "proceed" ] || echo "escalating to a human"
```

---

## 4. Sharpen it (optional)

Everything past here is additive; `augur` works without any of it.

| Want | Do this | Guide |
|------|---------|-------|
| Per-line test-gap precision | `augur check --coverage lcov.info` | [Coverage](coverage.md) |
| Tune thresholds / weights / rules | Drop an `.augur.toml` at the repo root | [Configuration](configuration.md) |
| Faster repeat runs | `augur calibrate` then `augur check --cached` | [CLI reference](cli.md#calibrate) |
| Inline PR annotations | `augur check --sarif-out augur.sarif` | [CI integration](ci-integration.md) |
| Durable trust records | `augur check --json \| attest sign --from-augur -` | [CI integration](ci-integration.md) |

---

## What's next?

- [CLI reference](cli.md): every command, flag, exit code, and the JSON shape.
- [Signals](signals.md): what each of the eight signals catches and how to tune it.
- [Architecture](architecture.md): how the deterministic, zero-dependency engine works.
