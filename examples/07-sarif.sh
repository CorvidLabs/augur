#!/usr/bin/env bash
# 07-sarif.sh — emit SARIF 2.1.0 from a risky change and validate it.
#
# `augur check --sarif` projects the risk verdict into a SARIF 2.1.0 log that
# GitHub code scanning can ingest to annotate a PR inline. This script makes a
# deliberately risky working-tree change (a sensitive auth file, no test), emits
# SARIF, validates it parses as JSON, and shows the result level for the change.
#
# Level mapping: verdict block -> error, review -> warning, proceed -> note.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

AUGUR="$(augur_bin)"
REPO="/tmp/augur-example-07"
make_scratch_repo "$REPO"

# A risky working-tree change: edit the sensitive auth file with no test.
cat >> "$REPO/src/auth/token.swift" <<'EOF'
func mintToken(secret: String) -> String {
    return secret + "-signed"
}
EOF

OUT="$REPO/augur.sarif"

echo "== augur check --sarif --sarif-out augur.sarif =="
"$AUGUR" check -C "$REPO" --no-config --sarif --sarif-out "$OUT"
echo

echo "== validate it parses as JSON (python3 -m json.tool) =="
python3 -m json.tool "$OUT" >/dev/null && echo "  OK: valid JSON"
echo

echo "== key fields =="
python3 - "$OUT" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
print("  version :", doc["version"])
print("  schema  :", "$schema" in doc)
run = doc["runs"][0]
print("  driver  :", run["tool"]["driver"]["name"], run["tool"]["driver"]["semanticVersion"])
print("  rule    :", run["tool"]["driver"]["rules"][0]["id"])
print("  results :", len(run["results"]))
for r in run["results"]:
    uri = r["locations"][0]["physicalLocation"]["artifactLocation"]["uri"]
    region = r["locations"][0]["physicalLocation"].get("region", {})
    line = region.get("startLine", "-")
    print(f"  - {r['level']:<8} line {line:<4} {uri}  (risk {r['properties']['riskScore']})")
PY
echo

echo "== level for the risky auth change =="
python3 - "$OUT" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
for r in doc["runs"][0]["results"]:
    uri = r["locations"][0]["physicalLocation"]["artifactLocation"]["uri"]
    if "auth/token.swift" in uri:
        print(f"  {uri}: level={r['level']} verdict={r['properties']['verdict']}")
PY

echo
echo "Upload in CI with github/codeql-action/upload-sarif; see examples/workflows/sarif.yml."
echo "NOTE: code scanning upload on a PRIVATE repo requires GitHub Advanced Security (GHAS)."
