#!/usr/bin/env bash
# Tests for scripts/retired-check.sh — the CI net twin of the commit gate.
#
# WHY a CI net at all (ADR 0012): the PreToolUse hook only fires for commands Claude runs.
# A human committing in their own terminal, or a PR merged in the GitHub UI, never touches
# it. The durable layer has to sit server-side. This CLI is what the workflow template calls.
#
# The contract that matters: it must judge the SAME thing as the hook (lines ADDED relative
# to the PR base), because a CI net that is stricter than the local gate turns every PR red
# for residue nobody introduced, and one that is looser is a silent hole.

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"
CLI="$(cd "$DIR/../../scripts" && pwd)/retired-check.sh"

mkrepo() {
  REPO="$(mktemp -d)"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email t@t.test
  git -C "$REPO" config user.name tester
  mkdir -p "$REPO/src" "$REPO/docs" "$REPO/.bootstrap"
  printf 'const legacy = i.typeNo\n' > "$REPO/src/legacy.ts"
  git -C "$REPO" add -A >/dev/null; git -C "$REPO" commit -qm seed
  BASE="$(git -C "$REPO" rev-parse HEAD)"
}
arm() { printf 'typeNo | typeId | | Intent の識別子 (#88)\n' > "$REPO/.bootstrap/retired"; }
run_cli() {
  local out; out="$(cd "$REPO" && bash "$CLI" "$@" 2>&1)"; CLI_EXIT=$?
  CLI_OUT="$out"
}

# 1. No marker => exit 0 (a non-adopting repo's CI must not break).
mkrepo
printf 'const fresh = i.typeNo\n' > "$REPO/src/new.ts"
git -C "$REPO" add -A >/dev/null; git -C "$REPO" commit -qm change
run_cli "$BASE"
test_case "no marker: CI passes"
assert_eq 0 "$CLI_EXIT"

# 2. A newly added retired name fails the check and names file + replacement.
mkrepo; arm
printf 'const fresh = i.typeNo\n' > "$REPO/src/new.ts"
git -C "$REPO" add -A >/dev/null; git -C "$REPO" commit -qm change
run_cli "$BASE"
test_case "an added retired name fails the check"
assert_eq 1 "$CLI_EXIT"
case "$CLI_OUT" in *'src/new.ts'*) assert_eq ok ok ;; *) assert_eq 'names the file' "$CLI_OUT" ;; esac
case "$CLI_OUT" in *'typeId'*) assert_eq ok ok ;; *) assert_eq 'names the replacement' "$CLI_OUT" ;; esac

# 3. Pre-existing residue in a touched file does NOT fail (same rule as the hook).
mkrepo; arm
printf 'const legacy = i.typeNo\nconst unrelated = 1\n' > "$REPO/src/legacy.ts"
git -C "$REPO" add -A >/dev/null; git -C "$REPO" commit -qm change
run_cli "$BASE"
test_case "pre-existing residue does not fail CI"
assert_eq 0 "$CLI_EXIT"

# 4. A marker with no parseable entry => exit 0.
mkrepo
printf '# nothing armed\n' > "$REPO/.bootstrap/retired"
printf 'const fresh = i.typeNo\n' > "$REPO/src/new.ts"
git -C "$REPO" add -A >/dev/null; git -C "$REPO" commit -qm change
run_cli "$BASE"
test_case "an empty marker passes CI (declared no-op)"
assert_eq 0 "$CLI_EXIT"

# 5. Missing base ref => exit 2 (usage error, distinguishable from a violation).
mkrepo; arm
run_cli
test_case "no base ref is a usage error (exit 2), not a false pass"
assert_eq 2 "$CLI_EXIT"

# 6. Three-dot (merge-base) form — the reason the workflow template uses it.
#    Failure mode being pinned: the BASE branch performs the rename while this branch is open.
#    A two-dot diff (base tip -> HEAD) then reads this branch as if it RE-ADDED the retired
#    name it merely never touched, and the PR goes red for work nobody did on it. Three-dot
#    measures from the fork point, so a branch is only answerable for its own added lines.
mkrepo; arm
MAIN="$(git -C "$REPO" rev-parse --abbrev-ref HEAD)"
git -C "$REPO" checkout -qb feature
printf 'const mine = 1\n' > "$REPO/src/mine.ts"                # this branch: nothing retired
git -C "$REPO" add -A >/dev/null; git -C "$REPO" commit -qm mine
git -C "$REPO" checkout -q "$MAIN"
printf 'const legacy = i.typeId\n' > "$REPO/src/legacy.ts"     # base does the rename meanwhile
git -C "$REPO" add -A >/dev/null; git -C "$REPO" commit -qm rename-on-base
git -C "$REPO" checkout -q feature
run_cli "$MAIN...HEAD"
test_case "three-dot: a branch is judged only on what it added since the fork point"
assert_eq 0 "$CLI_EXIT"
run_cli "$MAIN"
test_case "two-dot would blame this branch for the base's rename (why the template uses three-dot)"
assert_eq 1 "$CLI_EXIT"

# 7. Docs exempt in CI too.
mkrepo; arm
printf '旧称 typeNo は typeId へ\n' > "$REPO/docs/glossary.md"
git -C "$REPO" add -A >/dev/null; git -C "$REPO" commit -qm docs
run_cli "$BASE"
test_case "docs are exempt in CI too"
assert_eq 0 "$CLI_EXIT"

finish
