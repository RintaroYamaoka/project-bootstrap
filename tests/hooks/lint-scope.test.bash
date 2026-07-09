#!/usr/bin/env bash
# Tests for hooks/lib/lint-scope.sh + the scoped behaviour of block-commit-if-lint-fails.sh.
#
# The lint gate used to lint the WHOLE TREE. A lane worktree carries every repo file, so a lane
# worker was blocked by lint debt in files it does not own — with no legitimate remedy inside its
# lane, which is exactly what pushed it to edit outside the lane (marketing-app 2026-07-09, M5).
# The signal must be the judged object: the files THIS COMMIT carries.
# Linters that cannot take file arguments (go/cargo) stay whole-tree and stay fail-closed.

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"
source "$DIR/../../hooks/lib/lint-scope.sh"

# --- unit: lint_script_tool ---------------------------------------------------
test_case "plain tool name"
assert_eq "eslint" "$(lint_script_tool 'eslint .')"
test_case "npx prefix stripped"
assert_eq "biome" "$(lint_script_tool 'npx biome check .')"
test_case "pnpm exec prefix stripped"
assert_eq "oxlint" "$(lint_script_tool 'pnpm exec oxlint src')"
test_case "path-qualified binary reduces to basename"
assert_eq "eslint" "$(lint_script_tool './node_modules/.bin/eslint .')"
# `next lint` changes semantics when handed file args -> must NOT be treated as scopable,
# otherwise we invent lint failures that do not exist.
test_case "unknown tool (next lint) is not scopable"
assert_eq "" "$(lint_script_tool 'next lint')"
test_case "shell script (exit 1) is not scopable"
assert_eq "" "$(lint_script_tool 'exit 1')"

# --- unit: lint_ext_ok --------------------------------------------------------
# `lint_ext_ok tool file; echo $?` — the exit code IS the value under test, so each assertion
# distinguishes accept (0) from reject (1). A `cmd && assert_eq 0 0 || assert_eq 0 1` shape would
# pass in BOTH branches (a green lie); keep the value explicit.
ext_ok() { lint_ext_ok "$1" "$2"; printf '%s' "$?"; }

test_case "eslint accepts .ts"
assert_eq 0 "$(ext_ok eslint src/a.ts)"
test_case "eslint rejects .md"
assert_eq 1 "$(ext_ok eslint README.md)"
test_case "biome accepts .json"
assert_eq 0 "$(ext_ok biome tsconfig.json)"
test_case "ruff accepts .py"
assert_eq 0 "$(ext_ok ruff a.py)"
test_case "ruff rejects .ts"
assert_eq 1 "$(ext_ok ruff a.ts)"
test_case "extensionless file rejected by eslint"
assert_eq 1 "$(ext_ok eslint Makefile)"

# --- unit: lint_scoped_base ---------------------------------------------------
SB="$(mktemp -d)"; mkdir -p "$SB/node_modules/.bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SB/node_modules/.bin/biome"; chmod +x "$SB/node_modules/.bin/biome"
test_case "biome check resolves to the local binary"
assert_eq "node_modules/.bin/biome check" "$(cd "$SB" && lint_scoped_base 'biome check .')"
test_case "biome lint keeps the lint subcommand"
assert_eq "node_modules/.bin/biome lint" "$(cd "$SB" && lint_scoped_base 'biome lint .')"
test_case "unresolvable tool yields empty base (caller falls back to whole tree)"
assert_eq "" "$(cd "$SB" && lint_scoped_base 'oxlint .')"

# --- integration: the hook scopes to the commit's files -----------------------
HOOK=block-commit-if-lint-fails.sh
setup_repo() {
  local tmp; tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  REPO="$(git -C "$tmp" rev-parse --show-toplevel)"
  git -C "$REPO" config user.email t@t.test
  git -C "$REPO" config user.name tester
  mkdir -p "$REPO/node_modules/.bin" "$REPO/src/auth"
  : > "$REPO/.bootstrap-lint"
  printf '{"scripts":{"lint":"biome check ."}}' > "$REPO/package.json"
  # fake biome: fails only when handed DEBT.js (that file carries the lint debt)
  cat > "$REPO/node_modules/.bin/biome" <<'FAKE'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in *DEBT.js) echo "DEBT.js: lint error" >&2; exit 1;; esac; done
exit 0
FAKE
  chmod +x "$REPO/node_modules/.bin/biome"
  echo x > "$REPO/DEBT.js"
  echo ok > "$REPO/src/auth/mine.ts"
  git -C "$REPO" add package.json DEBT.js src/auth/mine.ts .bootstrap-lint
  git -C "$REPO" commit -qm init
  RUN_DIR="$REPO"
}
input_json() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}' "$1" "$REPO"; }

# THE REGRESSION: a lane worker committing only its own file must not be blocked by
# pre-existing debt in a file it does not own.
setup_repo
echo edited > "$REPO/src/auth/mine.ts"; git -C "$REPO" add src/auth/mine.ts
test_case "unowned pre-existing debt does not block this commit"
run_hook "$HOOK" "$(input_json 'git commit -m x')"
assert_exit 0

# The commit's OWN file still blocks when it fails lint.
setup_repo
echo mutated > "$REPO/DEBT.js"; git -C "$REPO" add DEBT.js
test_case "lint failure in this commit's own file blocks"
run_hook "$HOOK" "$(input_json 'git commit -m x')"
assert_exit 2
assert_stderr_contains "DEBT.js"

# `git commit -a` sweeps in unstaged tracked modifications -> they are the commit's files too.
setup_repo
echo mutated > "$REPO/DEBT.js"   # tracked, modified, NOT staged
test_case "git commit -a catches the swept-in file's lint failure"
run_hook "$HOOK" "$(input_json 'git commit -am x')"
assert_exit 2

# Same state without -a: the commit does not carry DEBT.js.
setup_repo
echo mutated > "$REPO/DEBT.js"
echo edited > "$REPO/src/auth/mine.ts"; git -C "$REPO" add src/auth/mine.ts
test_case "plain git commit does not lint unstaged tracked debt"
run_hook "$HOOK" "$(input_json 'git commit -m x')"
assert_exit 0

# A commit carrying no lintable file at all: nothing to judge.
setup_repo
echo hi > "$REPO/README.md"; git -C "$REPO" add README.md
test_case "commit with no lintable file skips lint"
run_hook "$HOOK" "$(input_json 'git commit -m x')"
assert_exit 0
assert_stderr_contains "no biome-lintable file"

# Deleted files are not passed to the linter (it would error on a missing path).
setup_repo
git -C "$REPO" rm -q DEBT.js
test_case "deleted file is not handed to the linter"
run_hook "$HOOK" "$(input_json 'git commit -m x')"
assert_exit 0

# Unscopable linter (unknown script) keeps the whole-tree, fail-closed behaviour.
setup_repo
printf '{"scripts":{"lint":"exit 1"}}' > "$REPO/package.json"
echo edited > "$REPO/src/auth/mine.ts"; git -C "$REPO" add src/auth/mine.ts
test_case "unscopable linter still lints whole tree and blocks (fail-closed preserved)"
run_hook "$HOOK" "$(input_json 'git commit -m x')"
assert_exit 2
assert_stderr_contains "lane を出て"

finish
