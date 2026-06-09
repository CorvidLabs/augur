#!/usr/bin/env bash
# 06-trust-pipeline.sh — the end-to-end augur -> attest trust loop.
#
# augur scores the risk of a change (proceed / review / block); attest records
# that verdict as a portable, signed-or-unsigned provenance note keyed to the
# commit SHA, and gates on a policy. They compose over a pipe and never link.
#
#   augur check --json | attest sign --from-augur -   # record the trust
#   attest verify --policy .attest.json                # gate on it
#
# This demo proves the loop with REAL exit codes against a throwaway /tmp repo:
#   1. build augur (this repo) and attest (../attest),
#   2. create a scratch repo whose HEAD touches a sensitive `auth` file,
#   3. run `augur gate` and show the verdict + exit code,
#   4. pipe `augur check --json` into `attest sign --from-augur -` as an agent,
#   5. `attest log` the recorded provenance,
#   6. `attest verify` a policy that demands human approval for review+ verdicts
#      — it FAILs (exit 1) on the agent-only record, then PASSes (exit 0) once a
#      human-approved attestation is added to the commit.
#
# attest is a sibling tool at ../attest. If that checkout is absent this script
# prints a clear skip message and exits 0 (so it is safe to run anywhere).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

AUGUR="$(augur_bin)"

if ! ATTEST="$(attest_bin)"; then
    echo "skip: attest is not available."
    echo "      This demo needs the sibling CorvidLabs/attest checkout at ../attest"
    echo "      (or an 'attest' binary on PATH). Clone it next to augur and re-run."
    exit 0
fi

REPO="/tmp/augur-example-06"

# --- 1. a scratch repo whose HEAD touches a sensitive auth file --------------
rm -rf "$REPO"
mkdir -p "$REPO/src/auth"
git -C "$REPO" init -q
git -C "$REPO" config user.email "demo@augur.dev"
git -C "$REPO" config user.name "augur demo"

echo "# demo" > "$REPO/README.md"
git -C "$REPO" add -A
git -C "$REPO" commit -qm "init"
BASE="$(git -C "$REPO" rev-parse HEAD)"

echo "func mintToken() {}" > "$REPO/src/auth/token.swift"
git -C "$REPO" add -A
git -C "$REPO" commit -qm "feat: add auth token handling"
HEAD="$(git -C "$REPO" rev-parse HEAD)"
RANGE="$BASE..$HEAD"

echo "== 1) the change under review =="
echo "  range: $RANGE  (HEAD touches a sensitive auth path)"
echo

# --- 2. augur gate: print the verdict and the exit code ----------------------
echo "== 2) augur gate (the ephemeral verdict) =="
run_gate() {
    local threshold="$1"
    set +e
    "$AUGUR" gate -C "$REPO" --range "$RANGE" --threshold "$threshold"
    local code=$?
    set -e
    echo "  gate --threshold $threshold -> exit $code"
    echo
}
run_gate block    # auth-only change scores 'review' -> passes a block gate
run_gate review   # ...but a 'review' gate trips, so an agent must escalate

# --- 3. record the verdict as provenance: augur check --json | attest sign ---
echo "== 3) augur check --json | attest sign --from-augur - (agent records trust) =="
# --from-augur copies augur's verdict and maps riskScore (0..100) to
# confidence = 1 - riskScore/100. The agent also asserts that tests passed.
"$AUGUR" check -C "$REPO" --range "$RANGE" --json \
    | "$ATTEST" sign -C "$REPO" \
        --from-augur - \
        --commit "$HEAD" \
        --reviewer agent:claude \
        --tests-passed
echo

# --- 4. the recorded provenance ---------------------------------------------
echo "== 4) attest log (the durable trust record, stored in git notes) =="
"$ATTEST" log -C "$REPO" --commit "$HEAD"
echo

# --- 5. a policy that demands human approval for review+ verdicts ------------
cat > "$REPO/.attest.json" <<'EOF'
{
  "requireAttestation": true,
  "requireTestsPassed": true,
  "requireHumanApprovalWhenVerdictAtLeast": "review"
}
EOF

echo "== 5) attest verify: agent-only record FAILS the policy =="
echo "  policy: requireHumanApprovalWhenVerdictAtLeast = review"
set +e
"$ATTEST" verify -C "$REPO" --commit "$HEAD" --policy "$REPO/.attest.json"
FAIL_CODE=$?
set -e
echo "  attest verify -> exit $FAIL_CODE   (only an agent attested a 'review' change)"
echo

# --- 6. add a human-approved attestation, then verify PASSES -----------------
# Any human-approved attestation on the commit clears the rule — the human need
# not restate the verdict; recording the sign-off is enough.
echo "== 6) a human signs off, then attest verify PASSES =="
"$ATTEST" sign -C "$REPO" \
    --commit "$HEAD" \
    --reviewer human:leif \
    --confidence 0.8 \
    --human-approved \
    --tests-passed \
    --note "looked at the auth path; safe to ship"
echo
"$ATTEST" log -C "$REPO" --commit "$HEAD"
echo
set +e
"$ATTEST" verify -C "$REPO" --commit "$HEAD" --policy "$REPO/.attest.json"
PASS_CODE=$?
set -e
echo "  attest verify -> exit $PASS_CODE   (human approval now satisfies the policy)"
echo

echo "== summary =="
echo "  agent-only verify : exit $FAIL_CODE  (FAIL — escalate to a human)"
echo "  after human sign  : exit $PASS_CODE  (PASS — trust policy satisfied)"
echo
echo "augur scored the risk; attest recorded the trust and gated on it."
