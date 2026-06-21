#!/usr/bin/env bash
# Unit tests for hooks/lib/verification-drift.sh — the SessionStart doctor's
# "unverified trunk change" judge: source-face changes on the current branch with no
# verification judgment recorded, in a repo that adopted docs/verification/.
#
# This is VISIBILITY, not enforcement, so we assert on the presence/absence of the advisory
# text and on the SILENCE bars (no adoption / no source change / plan present / non-git).
# We build throwaway repos with a LOCAL refs/remotes/origin/main (no network — the lib
# never fetches), mirroring repo-drift.test.bash.

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"
source "$(cd "$DIR/../../hooks" && pwd)/lib/verification-drift.sh"

git config --global user.email >/dev/null 2>&1 || git config --global user.email "test@example.com"
git config --global user.name  >/dev/null 2>&1 || git config --global user.name  "test"

# mkrepo — fresh repo, one commit on main, docs/verification/ NOT yet adopted. echoes path.
mkrepo() {
  local r; r="$(mktemp -d)"
  git -C "$r" init -q -b main
  git -C "$r" -c user.email=t@e.x -c user.name=t commit -q --allow-empty -m c0
  printf '%s' "$r"
}
adopt() { mkdir -p "$1/docs/verification"; }
commit_file() { # commit_file <repo> <path> <content>
  printf '%s\n' "$3" > "$1/$2"
  git -C "$1" add "$2"
  git -C "$1" -c user.email=t@e.x -c user.name=t commit -q -m "add $2"
}
spoke() { case "$1" in *"未判断の trunk source"*) return 0 ;; *) return 1 ;; esac; }

# 1. Adopted + uncommitted source + no plan => speaks. (Also the local-only / no-origin
#    case: mkrepo has no origin ref, so only the uncommitted path can fire — it must.)
R="$(mkrepo)"; adopt "$R"
printf 'export const x = 1\n' > "$R/app.ts"
OUT="$(verification_drift_report "$R")"
test_case "adopted + uncommitted source + no plan speaks"
if spoke "$OUT"; then assert_eq spoke spoke; else assert_eq spoke silent; fi
test_case "report names the triggering source file"
case "$OUT" in *"app.ts"*) assert_eq ok ok ;; *) assert_eq ok FAIL ;; esac

# 2. Doc-only change => silent.
R="$(mkrepo)"; adopt "$R"
printf '# notes\n' > "$R/README.md"
test_case "doc-only change is silent"
assert_eq "" "$(verification_drift_report "$R")"

# 3. A non-empty plan (>=1 row) for the branch => silent (the decision is being made).
R="$(mkrepo)"; adopt "$R"
printf 'export const x = 1\n' > "$R/app.ts"
printf 'DROP | unit | trivial | n/a | ai | low risk, internal\n' > "$R/docs/verification/main.md"
test_case "recorded judgment (non-empty plan) is silent"
assert_eq "" "$(verification_drift_report "$R")"

# 4. docs/verification not adopted => silent (opt-in), even with source changes.
R="$(mkrepo)"
printf 'export const x = 1\n' > "$R/app.ts"
test_case "no verification adoption is silent (opt-in)"
assert_eq "" "$(verification_drift_report "$R")"

# 5. Empty (comment-only) plan => speaks (a ritual file is not a judgment).
R="$(mkrepo)"; adopt "$R"
printf 'export const x = 1\n' > "$R/app.ts"
printf '# verification plan — nothing here yet\n' > "$R/docs/verification/main.md"
OUT="$(verification_drift_report "$R")"
test_case "empty comment-only plan still speaks"
if spoke "$OUT"; then assert_eq spoke spoke; else assert_eq spoke silent; fi

# 6. Clean tree, no source change => silent.
R="$(mkrepo)"; adopt "$R"
test_case "clean tree is silent"
assert_eq "" "$(verification_drift_report "$R")"

# 7. Committed-ahead source vs origin/main + no plan => speaks (tests the committed path
#    specifically: the working tree is clean after the commit).
R="$(mkrepo)"; adopt "$R"
git -C "$R" update-ref refs/remotes/origin/main "$(git -C "$R" rev-parse HEAD)"
commit_file "$R" feature.ts 'export const y = 2'
OUT="$(verification_drift_report "$R")"
test_case "committed-ahead source vs origin/main speaks"
if spoke "$OUT"; then assert_eq spoke spoke; else assert_eq spoke silent; fi

# 8. Committed-ahead but doc-only => silent.
R="$(mkrepo)"; adopt "$R"
git -C "$R" update-ref refs/remotes/origin/main "$(git -C "$R" rev-parse HEAD)"
commit_file "$R" NOTES.md '# doc only'
test_case "committed-ahead doc-only is silent"
assert_eq "" "$(verification_drift_report "$R")"

# 9. Non-git dir => silent (fail-open).
NG="$(mktemp -d)"; mkdir -p "$NG/docs/verification"; printf 'x\n' > "$NG/app.ts"
test_case "non-git dir is silent"
assert_eq "" "$(verification_drift_report "$NG")"

finish
