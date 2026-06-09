#!/usr/bin/env bash
# 01-check.sh — run `augur check` against a fresh scratch repo.
#
# Builds a /tmp repo with a few commits, makes a working-tree change to a
# sensitive auth file, and prints augur's verdict (human + JSON).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

AUGUR="$(augur_bin)"
REPO="/tmp/augur-example-01"
make_scratch_repo "$REPO"

# An uncommitted change to a sensitive file with no accompanying test.
echo "// new logic" >> "$REPO/src/auth/token.swift"

echo "== human report =="
"$AUGUR" check -C "$REPO"

echo
echo "== verbose (every signal) =="
"$AUGUR" check -C "$REPO" --verbose

echo
echo "== JSON (agent-friendly) =="
"$AUGUR" check -C "$REPO" --json
