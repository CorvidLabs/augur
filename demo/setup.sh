#!/usr/bin/env bash
# Builds a throwaway git repo that augur can assess, reproducing the verdict
# shown in demo/demo.gif. The repo carries a short history (including one revert,
# which augur reads as a past incident) and an uncommitted edit to a sensitive
# file, so `augur check` lands on REVIEW. Safe to re-run: it wipes and rebuilds.
#
#   ./demo/setup.sh            # builds the scratch repo at /tmp/demo-augur
#   ./demo/setup.sh /path/dir  # or at a directory you choose
set -euo pipefail

DIR="${1:-/tmp/demo-augur}"
rm -rf "$DIR"
mkdir -p "$DIR"
cd "$DIR"

git init -q
git config user.name  "demo"
git config user.email "demo@example.com"
git config commit.gpgsign false

commit() { git add -A && git commit -q -m "$1"; }

# A handful of ordinary feature commits across a few modules.
for n in 1 2 3 4 5; do
    mkdir -p "src/module$n"
    printf 'func feature%s() {}\n' "$n" > "src/module$n/feature.swift"
    commit "Add module $n"
done

# An auth/session change, then a tweak, then a revert of that tweak. augur reads
# the revert as a past incident on this area of the tree, which sharpens the
# history calibration in the verdict.
mkdir -p src/auth
printf 'func startSession() {}\n' > src/auth/session.swift
commit "feat: add auth session"
printf 'func startSession() { configure() }\n' > src/auth/session.swift
commit "tweak session"
git revert --no-edit HEAD >/dev/null

# A sensitive file that matches augur's built-in 'secrets' category.
{
    echo '// credential rotation'
    echo 'import Foundation'
    for i in $(seq 1 60); do
        echo "func rotateSecret$i(token: String, password: String) -> String { token + password }"
    done
} > src/auth/credentials.swift
commit "feat: add credential rotation"

# Leave an UNCOMMITTED edit to the sensitive file. This is the working-tree
# change `augur check` (no flags) assesses, and why it returns REVIEW.
{
    echo "func rotateSecret61(token: String, password: String) -> String { token + password }"
    echo "func rotateSecret62(token: String, password: String) -> String { token + password }"
    echo "func rotateSecret63(token: String, password: String) -> String { password + token }"
} >> src/auth/credentials.swift

echo "scratch repo ready at $DIR"
echo "run:  (cd $DIR && augur check)"
