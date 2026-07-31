#!/usr/bin/env bash
# Tests for hooks/block-commit-if-retired-term.sh
#
# The gate: on `git commit`, block when a line the commit NEWLY ADDS contains a name the
# project has registered as retired (`.bootstrap/retired`). Born from the ai-reception
# `Intent.typeNo` incident — a rename that a PR merged 1h12m later did not know about, which
# then sat broken and silent for three days.
#
# The behaviours that actually carry the design (each has a failure mode that would make the
# gate worse than useless):
#   - no marker => completely silent (a non-adopting repo must not notice this exists)
#   - pre-existing residue must NOT block: otherwise the actor's cheapest escapes are an
#     out-of-lane mass rename or deleting the marker, and the gate manufactures its bypass
#   - the rename commit itself must NOT block: the retired name is only being removed
#   - docs must NOT block: a glossary/ADR/incident legitimately names the retired thing
#   - the block message must name the REPLACEMENT (constructive advice — never "hide it")
#   - unparseable command => fail-CLOSED (a blocking gate must not be silenced by a payload)

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"

HOOK=block-commit-if-retired-term.sh
input_json() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}' "$1" "${RUN_DIR:-$PWD}"; }

# fresh_repo — a real git repo with one committed file carrying pre-existing residue.
fresh_repo() {
  RUN_DIR="$(mktemp -d)"
  git -C "$RUN_DIR" init -q
  git -C "$RUN_DIR" config user.email t@t.test
  git -C "$RUN_DIR" config user.name tester
  mkdir -p "$RUN_DIR/src" "$RUN_DIR/docs" "$RUN_DIR/.bootstrap"
  printf 'const legacy = i.typeNo\n' > "$RUN_DIR/src/legacy.ts"
  git -C "$RUN_DIR" add -A >/dev/null
  git -C "$RUN_DIR" commit -qm seed
}
arm() { printf 'typeNo | typeId | | Intent の識別子 (#88)\n' > "$RUN_DIR/.bootstrap/retired"; }

# 1. Non-commit command passes through.
fresh_repo; arm
test_case "non-commit command passes through"
run_hook "$HOOK" "$(input_json 'git status')"
assert_exit 0

# 2. No marker => silent pass, even with the retired name freshly added.
fresh_repo
printf 'const fresh = i.typeNo\n' > "$RUN_DIR/src/new.ts"
git -C "$RUN_DIR" add src/new.ts
test_case "no marker: the gate is completely off"
run_hook "$HOOK" "$(input_json 'git commit -m x')"
assert_exit 0
assert_stderr_contains ""

# 3. A newly added line carrying the retired name blocks, and names the replacement.
fresh_repo; arm
printf 'const fresh = i.typeNo\n' > "$RUN_DIR/src/new.ts"
git -C "$RUN_DIR" add src/new.ts
test_case "a newly added retired name blocks the commit"
run_hook "$HOOK" "$(input_json 'git commit -m x')"
assert_exit 2
assert_stderr_contains "typeNo"
assert_stderr_contains "typeId"
assert_stderr_contains "src/new.ts"

# 4. Pre-existing residue does NOT block (the load-bearing case).
fresh_repo; arm
printf 'const legacy = i.typeNo\nconst unrelated = 1\n' > "$RUN_DIR/src/legacy.ts"
git -C "$RUN_DIR" add src/legacy.ts
test_case "touching a file with pre-existing residue does not block"
run_hook "$HOOK" "$(input_json 'git commit -m x')"
assert_exit 0

# 5. The rename itself does NOT block.
fresh_repo; arm
printf 'const legacy = i.typeId\n' > "$RUN_DIR/src/legacy.ts"
git -C "$RUN_DIR" add src/legacy.ts
test_case "the rename commit itself is allowed"
run_hook "$HOOK" "$(input_json 'git commit -m rename')"
assert_exit 0

# 6. Docs are exempt.
fresh_repo; arm
printf '旧称 typeNo は typeId に改名した\n' > "$RUN_DIR/docs/glossary.md"
git -C "$RUN_DIR" add docs/glossary.md
test_case "a doc that names the retired term is exempt"
run_hook "$HOOK" "$(input_json 'git commit -m docs')"
assert_exit 0

# 7. A near-miss identifier does not block.
fresh_repo; arm
printf 'const typeNotation = 1\n' > "$RUN_DIR/src/new.ts"
git -C "$RUN_DIR" add src/new.ts
test_case "a longer identifier containing the term does not block"
run_hook "$HOOK" "$(input_json 'git commit -m x')"
assert_exit 0

# 8. `git commit -a` sweeps unstaged tracked changes into the scan.
fresh_repo; arm
printf 'const legacy = i.typeNo\nconst sneaky = i.typeNo\n' > "$RUN_DIR/src/legacy.ts"   # unstaged
test_case "git commit -a scans the unstaged tracked change it will sweep in"
run_hook "$HOOK" "$(input_json 'git commit -am x')"
assert_exit 2
test_case "a plain commit does not scan that unstaged change"
run_hook "$HOOK" "$(input_json 'git commit -m x')"
assert_exit 0

# 9. A marker with no parseable entry is a declared no-op => pass (doctor reports it).
fresh_repo
printf '# nothing armed yet\n' > "$RUN_DIR/.bootstrap/retired"
printf 'const fresh = i.typeNo\n' > "$RUN_DIR/src/new.ts"
git -C "$RUN_DIR" add src/new.ts
test_case "an empty marker does not block (declared no-op; doctor surfaces it)"
run_hook "$HOOK" "$(input_json 'git commit -m x')"
assert_exit 0

# 10. Legacy flat marker path still arms the gate.
fresh_repo
printf 'typeNo | typeId\n' > "$RUN_DIR/.bootstrap-retired"
printf 'const fresh = i.typeNo\n' > "$RUN_DIR/src/new.ts"
git -C "$RUN_DIR" add src/new.ts
test_case "the legacy flat marker path also arms the gate"
run_hook "$HOOK" "$(input_json 'git commit -m x')"
assert_exit 2

# 11. Scope-glob narrows the ban.
fresh_repo
printf 'legacyFlag | featureFlag | src/**\n' > "$RUN_DIR/.bootstrap/retired"
mkdir -p "$RUN_DIR/vendor"
printf 'const a = legacyFlag\n' > "$RUN_DIR/vendor/v.ts"
git -C "$RUN_DIR" add vendor/v.ts
test_case "a path outside the scope-glob is not blocked"
run_hook "$HOOK" "$(input_json 'git commit -m x')"
assert_exit 0
printf 'const a = legacyFlag\n' > "$RUN_DIR/src/in.ts"
git -C "$RUN_DIR" add src/in.ts
test_case "a path inside the scope-glob is blocked"
run_hook "$HOOK" "$(input_json 'git commit -m x')"
assert_exit 2

# 12. Unparseable command => fail-CLOSED (matches the other blocking commit gates).
fresh_repo; arm
test_case "unparseable hook input blocks (fail-closed)"
run_hook "$HOOK" 'not json at all'
assert_exit 2

# 13. Outside a git repo => fail-open (no basis to judge).
RUN_DIR="$(mktemp -d)"
test_case "outside a git repo the gate falls open"
run_hook "$HOOK" "$(input_json 'git commit -m x')"
assert_exit 0

finish
