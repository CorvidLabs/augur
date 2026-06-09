#!/usr/bin/env bash
# 02-gate-ci.sh — demonstrate `augur gate` exit codes for CI / agent loops.
#
# `gate` exits non-zero when the verdict meets or exceeds a threshold, so a CI
# step or agent can escalate instead of merging blind.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

AUGUR="$(augur_bin)"
REPO="/tmp/augur-example-02"
make_scratch_repo "$REPO"

echo "// change to a sensitive path" >> "$REPO/src/auth/token.swift"

run_gate() {
    local threshold="$1"
    set +e
    "$AUGUR" gate -C "$REPO" --threshold "$threshold"
    local code=$?
    set -e
    echo "  gate --threshold $threshold -> exit $code"
    echo
}

echo "== gate at each threshold =="
run_gate proceed   # exits 1 for anything above proceed
run_gate review    # exits 1 if review or block
run_gate block     # exits 1 only on block

echo "Use a non-zero exit to fail a CI job or trigger an agent escalation."
