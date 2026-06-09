#!/usr/bin/env bash
# 08-coverage-formats.sh — JaCoCo and Go coverprofile sharpen the test-gap signal.
#
# Companion to 05-coverage.sh (which covers LCOV + Cobertura). The SAME working-tree
# change is assessed with a coverage report that marks the changed lines COVERED vs
# UNCOVERED, for each of the two newer formats:
#   1. JaCoCo XML (Kotlin/Java)   — covered (ci>0) lowers the gap; uncovered (ci=0) raises it
#   2. Go coverprofile            — covered (count>0) lowers the gap; uncovered (count=0) raises it
#
# augur reports the test-gap signal as "<covered>/<instrumented> changed lines
# covered (NN%)" when a report is supplied.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

AUGUR="$(augur_bin)"

score() {
    "$AUGUR" check "$@" --json 2>/dev/null | grep -o '"riskScore" : [0-9.]*' | head -1
}
detail() {
    "$AUGUR" check "$@" --json 2>/dev/null \
        | grep -o '"detail" : "[0-9]*/[0-9]* changed lines covered[^"]*"' | head -1 || true
}

# ---------------------------------------------------------------------------
# JaCoCo (Kotlin/Java)
# ---------------------------------------------------------------------------
KREPO="/tmp/augur-example-08-jacoco"
make_scratch_repo "$KREPO"

# Commit a Kotlin source file, then append a new function (added lines 4,5,6).
cat > "$KREPO/Bar.kt" <<'EOF'
fun add(a: Int, b: Int): Int {
    return a + b
}
EOF
git -C "$KREPO" add -A
git -C "$KREPO" commit -qm "Add Bar.kt"
cat >> "$KREPO/Bar.kt" <<'EOF'
fun sub(a: Int, b: Int): Int {
    return a - b
}
EOF

# JaCoCo report: package "" + sourcefile "Bar.kt" => path "Bar.kt" (suffix-matches the diff).
# ci>0 == covered instructions. Here the changed lines 4,5,6 are COVERED.
cat > "$KREPO/jacoco.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<report name="app">
  <package name="">
    <sourcefile name="Bar.kt">
      <line nr="1" mi="0" ci="2"/>
      <line nr="4" mi="0" ci="3"/>
      <line nr="5" mi="0" ci="3"/>
      <line nr="6" mi="0" ci="3"/>
    </sourcefile>
  </package>
</report>
EOF

echo "== JaCoCo: changed lines COVERED (ci>0) =="
detail -C "$KREPO" --no-config --coverage "$KREPO/jacoco.xml"
JACOCO_COVERED="$(score -C "$KREPO" --no-config --coverage "$KREPO/jacoco.xml")"
echo "  $JACOCO_COVERED"

# Same lines, but UNCOVERED (ci=0, misses only).
cat > "$KREPO/jacoco-bad.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<report name="app">
  <package name="">
    <sourcefile name="Bar.kt">
      <line nr="4" mi="3" ci="0"/>
      <line nr="5" mi="3" ci="0"/>
      <line nr="6" mi="3" ci="0"/>
    </sourcefile>
  </package>
</report>
EOF

echo
echo "== JaCoCo: changed lines UNCOVERED (ci=0) =="
"$AUGUR" check -C "$KREPO" --no-config --coverage "$KREPO/jacoco-bad.xml" -v 2>/dev/null \
    | grep -E 'test-gap' || true
JACOCO_UNCOVERED="$(score -C "$KREPO" --no-config --coverage "$KREPO/jacoco-bad.xml")"
echo "  $JACOCO_UNCOVERED"

echo
echo "== JaCoCo auto-detect (jacoco.xml at repo root, no flag) =="
"$AUGUR" check -C "$KREPO" --no-config 2>&1 >/dev/null | grep coverage || true

# ---------------------------------------------------------------------------
# Go coverprofile
# ---------------------------------------------------------------------------
GREPO="/tmp/augur-example-08-go"
make_scratch_repo "$GREPO"

cat > "$GREPO/calc.go" <<'EOF'
package main

func add(a, b int) int {
	return a + b
}
EOF
git -C "$GREPO" add -A
git -C "$GREPO" commit -qm "Add calc.go"
cat >> "$GREPO/calc.go" <<'EOF'

func sub(a, b int) int {
	return a - b
}
EOF

# go test -coverprofile format: mode line + "path:start.col,end.col stmts count".
# The block over the changed lines (6..9) has count>0 => COVERED.
cat > "$GREPO/cover.out" <<'EOF'
mode: set
github.com/x/calc/calc.go:6.1,9.2 2 5
EOF

echo
echo "== Go coverprofile: changed lines COVERED (count>0) =="
detail -C "$GREPO" --no-config --coverage "$GREPO/cover.out"
GO_COVERED="$(score -C "$GREPO" --no-config --coverage "$GREPO/cover.out")"
echo "  $GO_COVERED"

# Same block, count=0 => UNCOVERED.
cat > "$GREPO/cover-bad.out" <<'EOF'
mode: set
github.com/x/calc/calc.go:6.1,9.2 2 0
EOF

echo
echo "== Go coverprofile: changed lines UNCOVERED (count=0) =="
"$AUGUR" check -C "$GREPO" --no-config --coverage "$GREPO/cover-bad.out" -v 2>/dev/null \
    | grep -E 'test-gap' || true
GO_UNCOVERED="$(score -C "$GREPO" --no-config --coverage "$GREPO/cover-bad.out")"
echo "  $GO_UNCOVERED"

echo
echo "== Go auto-detect (cover.out at repo root, no flag) =="
"$AUGUR" check -C "$GREPO" --no-config 2>&1 >/dev/null | grep coverage || true

echo
echo "Summary: covered changed lines lower the test-gap risk; uncovered raise it."
echo "  JaCoCo covered   : $JACOCO_COVERED"
echo "  JaCoCo uncovered : $JACOCO_UNCOVERED"
echo "  Go     covered   : $GO_COVERED"
echo "  Go     uncovered : $GO_UNCOVERED"
