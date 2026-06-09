#!/usr/bin/env bash
# 05-coverage.sh — show how per-line coverage sharpens the test-gap signal.
#
# The SAME working-tree change to a source file is assessed three ways:
#   1. no coverage          -> coarse heuristic (code changed, no test => high gap)
#   2. lcov.info, covered   -> the changed lines ARE covered  => low gap
#   3. coverage.xml, none   -> the changed lines are NOT covered => high gap
#
# augur reports the test-gap signal as "<covered>/<instrumented> changed lines
# covered (NN%)" when a report is supplied.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

AUGUR="$(augur_bin)"
REPO="/tmp/augur-example-05"
make_scratch_repo "$REPO"

# Commit a small source file so we can make a clean, single-hunk working-tree
# change with known line numbers.
cat > "$REPO/src/calc.swift" <<'EOF'
func add(_ a: Int, _ b: Int) -> Int {
    return a + b
}
EOF
git -C "$REPO" add -A
git -C "$REPO" commit -qm "Add calc"

# Append three new lines (these become added lines 4,5,6 in the new revision).
cat >> "$REPO/src/calc.swift" <<'EOF'
func sub(_ a: Int, _ b: Int) -> Int {
    return a - b
}
EOF

score() {
    "$AUGUR" check "$@" --json 2>/dev/null | grep -o '"riskScore" : [0-9.]*' | head -1
}

echo "== 1) no coverage (heuristic test-gap) =="
"$AUGUR" check -C "$REPO" --no-config --no-config -v 2>/dev/null \
    | sed -n '/calc.swift/,/test-gap/p' | grep -E 'calc.swift|test-gap' || true
NO_COV="$(score -C "$REPO" --no-config --no-coverage)"
echo "  $NO_COV"

# An LCOV report where the changed lines (4,5,6) are COVERED.
cat > "$REPO/lcov.info" <<'EOF'
TN:
SF:src/calc.swift
DA:1,3
DA:2,3
DA:4,5
DA:5,5
DA:6,5
end_of_record
EOF

echo
echo "== 2) lcov.info, changed lines covered =="
# When fully covered the test-gap risk is 0 (the verbose reporter omits zero
# signals), so we read the detail straight from JSON.
"$AUGUR" check -C "$REPO" --no-config --coverage "$REPO/lcov.info" --json 2>/dev/null \
    | grep -o '"detail" : "[0-9]*/[0-9]* changed lines covered[^"]*"' | head -1 || true
COVERED="$(score -C "$REPO" --no-config --coverage "$REPO/lcov.info")"
echo "  $COVERED"

# A Cobertura report where the changed lines (4,5,6) are NOT covered.
cat > "$REPO/coverage.xml" <<'EOF'
<?xml version="1.0"?>
<coverage>
  <packages>
    <package name="app">
      <classes>
        <class filename="src/calc.swift">
          <lines>
            <line number="1" hits="3"/>
            <line number="2" hits="3"/>
            <line number="4" hits="0"/>
            <line number="5" hits="0"/>
            <line number="6" hits="0"/>
          </lines>
        </class>
      </classes>
    </package>
  </packages>
</coverage>
EOF

echo
echo "== 3) coverage.xml, changed lines uncovered =="
"$AUGUR" check -C "$REPO" --no-config --coverage "$REPO/coverage.xml" -v 2>/dev/null \
    | grep -E 'test-gap' || true
UNCOVERED="$(score -C "$REPO" --no-config --coverage "$REPO/coverage.xml")"
echo "  $UNCOVERED"

echo
echo "== auto-detect (lcov.info present at repo root, no flag) =="
# Remove coverage.xml so only lcov.info is auto-detected.
rm -f "$REPO/coverage.xml"
"$AUGUR" check -C "$REPO" --no-config 2>&1 >/dev/null | grep coverage || true

echo
echo "Summary: covered changed lines lower the test-gap risk; uncovered raise it."
echo "  no coverage : $NO_COV"
echo "  covered     : $COVERED"
echo "  uncovered   : $UNCOVERED"
