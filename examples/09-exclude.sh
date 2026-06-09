#!/usr/bin/env bash
# 09-exclude.sh — drop generated/vendored noise from the assessment.
#
# A change touches a small reviewable source file AND a churny vendored
# lockfile that no human should be scored on. We assess the STAGED change three
# ways:
#   1. with everything scored (--no-config --no-exclude),
#   2. excluding the vendored path ad-hoc with --exclude,
#   3. excluding it via [exclude] in an auto-discovered .augur.toml.
# The vendored file vanishes from the verdict in (2) and (3): it appears in
# neither the files list nor any signal, and is reported as "excluded: N files".
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

AUGUR="$(augur_bin)"
REPO="/tmp/augur-example-09"
make_scratch_repo "$REPO"

# A small, reviewable source change...
echo "// a small tweak" >> "$REPO/src/module1.swift"

# ...alongside a large vendored lockfile drop that should NOT be scored.
mkdir -p "$REPO/vendor/some-dep"
python3 - "$REPO/vendor/some-dep/Package.resolved" <<'PY'
import sys
# A big, noisy generated lockfile — exactly the kind of churn we want to ignore.
with open(sys.argv[1], "w") as f:
    f.write('{\n  "pins": [\n')
    f.write(",\n".join('    {"identity": "dep%d", "revision": "%040d"}' % (i, i) for i in range(400)))
    f.write("\n  ]\n}\n")
PY

# Stage both so they appear in the diff (a new vendored file is untracked
# otherwise); we assess the staged index as a pre-commit check would.
git -C "$REPO" add -A

echo "== (1) everything scored (--no-exclude) =="
"$AUGUR" check -C "$REPO" --staged --no-config --no-exclude

echo
echo "== (2) exclude the vendored lockfile ad-hoc (--exclude 'vendor/**') =="
"$AUGUR" check -C "$REPO" --staged --no-config --exclude 'vendor/**'

# Now make the exclusion permanent via .augur.toml (auto-discovered).
cat > "$REPO/.augur.toml" <<'EOF'
[exclude]
paths = ["vendor/**", "**/*.generated.swift", "**/Package.resolved"]
EOF

echo
echo "== (3) exclude via .augur.toml [exclude] (auto-discovered) =="
# The "config:"/"exclude:" notes print to stderr; the report to stdout.
"$AUGUR" check -C "$REPO" --staged

echo
echo "== JSON confirms the dropped path under excludedPaths =="
"$AUGUR" check -C "$REPO" --staged --json | grep -A2 '"excludedPaths"' || true

echo
echo "The vendored lockfile is gone from the verdict in (2) and (3):"
echo "it is reported as 'excluded' and contributes nothing to the score."
