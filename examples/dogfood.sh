#!/usr/bin/env bash
# dogfood.sh — augur runs augur on itself, with BOTH outcomes proven.
#
# This is the self-contained proof behind docs/dogfooding.md. It:
#   1. runs `augur check` on THIS augur repo over a real git range and prints
#      the real verdict (a low-risk PROCEED — augur trusts its own change), and
#   2. builds a controlled risky change in a throwaway /tmp repo (a sensitive
#      secrets/auth file plus a large untested diff) and runs `augur gate
#      --threshold review`, which EXITS NON-ZERO. That non-zero exit is the
#      whole point — it is captured and expected, not a script failure.
#
# The script itself succeeds (exit 0). The gate's non-zero exit is surfaced as
# data, so you can see augur catch a genuinely risky change for real.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

AUGUR="$(augur_bin)"
REPO_ROOT="$(cd .. && pwd)"

rule() { printf '%s\n' "------------------------------------------------------------"; }

# Run a gate and report its exit code without tripping `set -e`.
gate() {
    local label="$1"; shift
    set +e
    "$AUGUR" gate "$@"
    local code=$?
    set -e
    echo "  → $label: gate exit $code"
    return 0
}

# === 1. augur assesses augur — the real repo, the real verdict ===============
rule
echo "1) augur scores augur (this repo)"
rule
# Prefer diffing against origin/main; fall back to the last commit; never error.
RANGE=''
if git -C "$REPO_ROOT" rev-parse --verify -q origin/main >/dev/null; then
    RANGE='origin/main..HEAD'
elif git -C "$REPO_ROOT" rev-parse --verify -q HEAD~1 >/dev/null; then
    RANGE='HEAD~1..HEAD'
fi

# If origin/main..HEAD is empty (e.g. running straight on main, or before the
# branch has commits), fall back to the last commit so the demo always shows a
# real assessment rather than an empty diff.
if [ -n "$RANGE" ] \
    && [ -z "$(git -C "$REPO_ROOT" diff --name-only "$RANGE" 2>/dev/null)" ] \
    && git -C "$REPO_ROOT" rev-parse --verify -q HEAD~1 >/dev/null; then
    RANGE='HEAD~1..HEAD'
fi

if [ -n "$RANGE" ]; then
    echo "range: $RANGE"
    echo
    "$AUGUR" check -C "$REPO_ROOT" --range "$RANGE"
    echo
    # A self-change should not be block-level; gate at `block` and expect pass.
    gate "augur self-gate at --threshold block (expect pass / exit 0)" \
        -C "$REPO_ROOT" --range "$RANGE" --threshold block
else
    echo "No prior commit to diff against (first commit) — skipping self-check."
fi
echo

# === 2. augur CATCHES a risky change — non-zero gate, for real ===============
rule
echo "2) augur catches a risky change (throwaway /tmp repo)"
rule
RISKY="/tmp/augur-dogfood-risky"
make_scratch_repo "$RISKY"
BASE="$(git -C "$RISKY" rev-parse HEAD)"

# A genuinely risky change: a sensitive secrets/auth file with a hard-coded
# credential AND a large block of untested functions — exactly what augur's
# sensitivity + diff-shape + test-gap signals are built to flag.
{
    echo 'let API_SECRET = "sk-live-DO-NOT-COMMIT-aaaaaaaaaaaaaaaa"'
    for i in $(seq 1 80); do
        echo "func untestedHandler$i() { /* no test covers this */ }"
    done
} > "$RISKY/src/auth/secrets.swift"
git -C "$RISKY" add -A
git -C "$RISKY" commit -qm "add secret handling + 80 untested funcs"
HEAD="$(git -C "$RISKY" rev-parse HEAD)"
RISKY_RANGE="$BASE..$HEAD"

echo "range: $RISKY_RANGE  (HEAD adds a sensitive secrets file + untested code)"
echo
"$AUGUR" check -C "$RISKY" --range "$RISKY_RANGE"
echo

# The review-level risk trips a `--threshold review` gate: NON-ZERO ON PURPOSE.
gate "risky-change gate at --threshold review (EXPECT FAIL / exit 1)" \
    -C "$RISKY" --range "$RISKY_RANGE" --threshold review

# Capture the code explicitly so we can assert the demo actually proved a fail.
set +e
"$AUGUR" gate -C "$RISKY" --range "$RISKY_RANGE" --threshold review >/dev/null 2>&1
REVIEW_CODE=$?
set -e
echo

rule
echo "summary"
rule
echo "  augur on augur          : PROCEED-level, block gate passed (exit 0)"
echo "  augur on risky change   : REVIEW-level, review gate exit $REVIEW_CODE (non-zero = caught)"
echo
if [ "$REVIEW_CODE" -ne 0 ]; then
    echo "augur dogfooded itself: trusted its own change AND caught a risky one."
else
    echo "ERROR: the risky-change gate did not fail as expected." >&2
    exit 1
fi
