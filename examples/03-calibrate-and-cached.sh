#!/usr/bin/env bash
# 03-calibrate-and-cached.sh — cache the history model, then reuse it.
#
# `augur calibrate` walks git history once and writes .augur/cache.json.
# `augur check --cached` reuses that cache instead of re-walking the log; if the
# cached HEAD differs from the current HEAD it prints a staleness warning to
# stderr but stays usable.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

AUGUR="$(augur_bin)"
REPO="/tmp/augur-example-03"
make_scratch_repo "$REPO"

echo "== calibrate (walks history once, writes .augur/cache.json) =="
"$AUGUR" calibrate -C "$REPO"
echo
echo "cache file:"
ls -l "$REPO/.augur/cache.json"

echo
echo "== check --cached (reuses the model, no git log walk) =="
echo "// edit" >> "$REPO/src/auth/token.swift"
"$AUGUR" check -C "$REPO" --cached

echo
echo "== make a new commit, then check --cached again (staleness warning) =="
echo "new file" > "$REPO/src/new.swift"
git -C "$REPO" add -A
git -C "$REPO" commit -qm "Add a new file (moves HEAD)"
echo "// another edit" >> "$REPO/src/auth/token.swift"
# The staleness note goes to stderr; the report still prints on stdout.
"$AUGUR" check -C "$REPO" --cached
