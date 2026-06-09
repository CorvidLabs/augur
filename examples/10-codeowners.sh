#!/usr/bin/env bash
# 10-codeowners.sh — CODEOWNERS-aware ownership scoring.
#
# augur reads a repo's CODEOWNERS file to flag review-routing gaps: a changed
# file with NO declared owner raises the `codeowners` signal, while an owned
# file neutralizes it. Repos without a CODEOWNERS file are never penalized.
#
# We stage two changes — an OWNED file under src/ and an UNOWNED file under
# lib/ — and assess them three ways:
#   1. with CODEOWNERS in effect (the unowned file scores higher),
#   2. with --no-codeowners (the signal goes neutral; scores converge),
#   3. JSON, to show the owner surfaced in the signal detail.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

AUGUR="$(augur_bin)"
REPO="/tmp/augur-example-10"
make_scratch_repo "$REPO"

# Declare ownership: src/ belongs to a backend team, docs to a docs team.
mkdir -p "$REPO/.github"
cat > "$REPO/.github/CODEOWNERS" <<'EOF'
# Backend owns the source tree; docs team owns markdown.
/src/   @backend-team
*.md    @docs-team
EOF
git -C "$REPO" add -A
git -C "$REPO" commit -qm "Add CODEOWNERS"

# An OWNED change (src/, owned by @backend-team)...
echo "// owned tweak" >> "$REPO/src/module1.swift"
# ...and an UNOWNED change (lib/, matched by no CODEOWNERS rule).
mkdir -p "$REPO/lib"
echo "let unowned = 1" > "$REPO/lib/helper.swift"
git -C "$REPO" add -A

echo "== (1) with CODEOWNERS — the unowned lib/ file scores higher =="
"$AUGUR" check -C "$REPO" --staged --no-config -v

echo
echo "== (2) with --no-codeowners — the signal is neutral for both =="
"$AUGUR" check -C "$REPO" --staged --no-config --no-codeowners -v

echo
echo "== (3) JSON — the owner is surfaced in the signal detail =="
"$AUGUR" check -C "$REPO" --staged --no-config --json \
  | grep -E '"path"|"name" : "codeowners"|"detail" : "(no CODEOWNERS owner|owned by)' || true

echo
echo "The unowned lib/helper.swift carries a 'no CODEOWNERS owner' signal;"
echo "src/module1.swift is 'owned by @backend-team' and neutralized."
