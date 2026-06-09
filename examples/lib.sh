#!/usr/bin/env bash
# Shared helpers for augur example scripts.
#
# Each example builds a self-contained scratch git repository under /tmp so the
# scripts actually run without touching your real repos.
set -euo pipefail

# Locate the augur binary: prefer an installed one, else build from this repo.
augur_bin() {
    if command -v augur >/dev/null 2>&1; then
        command -v augur
        return
    fi
    local root
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    # Always build (incremental — a no-op when up to date) so the demo never
    # runs a stale binary from an earlier checkout.
    ( cd "$root" && swift build >/dev/null )
    echo "$root/.build/debug/augur"
}

# Locate the attest binary: prefer an installed one, else build it from the
# sibling ../../attest checkout. Prints nothing and returns 1 if attest is
# unavailable (so callers can skip gracefully on a machine without the repo).
attest_bin() {
    if command -v attest >/dev/null 2>&1; then
        command -v attest
        return 0
    fi
    local root attest_root
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    attest_root="$(cd "$root/../attest" 2>/dev/null && pwd)" || return 1
    [[ -d "$attest_root" ]] || return 1
    # Always build (incremental) so the demo can't run a stale attest binary.
    ( cd "$attest_root" && swift build >/dev/null 2>&1 ) || return 1
    echo "$attest_root/.build/debug/attest"
}

# make_scratch_repo <dir>: create a fresh repo with a realistic history,
# including a sensitive auth file and a Revert commit (an "incident").
make_scratch_repo() {
    local dir="$1"
    rm -rf "$dir"
    mkdir -p "$dir"
    git -C "$dir" init -q
    git -C "$dir" config user.email "demo@augur.dev"
    git -C "$dir" config user.name "augur demo"

    mkdir -p "$dir/src/auth" "$dir/pkg/internal" "$dir/Tests"

    local i
    for i in 1 2 3 4 5 6; do
        echo "line $i" > "$dir/src/module$i.swift"
        git -C "$dir" add -A
        git -C "$dir" commit -qm "Add module $i"
    done

    echo "token logic" > "$dir/src/auth/token.swift"
    git -C "$dir" add -A
    git -C "$dir" commit -qm "feat: add auth token handling"

    echo "buggy" >> "$dir/src/auth/token.swift"
    git -C "$dir" add -A
    git -C "$dir" commit -qm "tweak token expiry"

    # An incident: revert the last commit (counts toward calibration).
    git -C "$dir" revert --no-edit HEAD >/dev/null

    echo "internal helper" > "$dir/pkg/internal/api.swift"
    git -C "$dir" add -A
    git -C "$dir" commit -qm "Add internal api helper"
}
