#!/usr/bin/env bash
# 04-custom-config.sh — show how .augur.toml changes the verdict.
#
# The same change is assessed twice: once with built-in defaults (--no-config)
# and once with a custom .augur.toml that tightens the thresholds and adds an
# "internal-api" sensitivity rule. The risk score is identical; the verdict
# changes because the cutoffs and rules changed.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

AUGUR="$(augur_bin)"
REPO="/tmp/augur-example-04"
make_scratch_repo "$REPO"

# A change to a path that the built-in rules do NOT flag, but our custom rule does.
echo "// internal change" >> "$REPO/pkg/internal/api.swift"

# Write a strict custom config into the repo (auto-discovered as .augur.toml).
cat > "$REPO/.augur.toml" <<'EOF'
[thresholds]
review = 10
block = 25

[[rules]]
label = "internal-api"
risk = 0.9
fragments = ["internal/", "private/"]
EOF

echo "== with built-in defaults (--no-config) =="
"$AUGUR" check -C "$REPO" --no-config

echo
echo "== with custom .augur.toml (auto-discovered) =="
# The "config: loaded ..." note prints to stderr; the report to stdout.
"$AUGUR" check -C "$REPO"

echo
echo "Same risk score, escalated verdict: tighter thresholds + a custom rule."
