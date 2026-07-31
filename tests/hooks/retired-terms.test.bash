#!/usr/bin/env bash
# Unit tests for hooks/lib/retired-terms.sh — the single authority on "did this change
# newly introduce a RETIRED name?" shared by the commit gate (block-commit-if-retired-term),
# the CI net (scripts/retired-check.sh) and the doctor's residual sweep. Three consumers
# reading the marker independently would drift on the matching rule, and the loosest one
# becomes the silent hole (same reason commit-files.sh / lane-match.sh are shared).
#
# Contract under test:
#   - the marker is line-oriented `term | replacement | scope-glob | note`; only the term
#     is required; `#` comments and blank lines are ignored; fields are trimmed
#   - an entry with an identifier-safe term matches on WORD boundaries (typeNo hits
#     `i.typeNo`, never `typeNotation`); a term containing anything else falls back to a
#     plain substring match (multibyte terms have no word boundary to anchor to)
#   - scope-glob narrows where a term is banned (AI の癖⑧: a rule without a scope
#     over-generalizes); an empty scope means the whole repo
#   - docs are exempt: a retired name legitimately appears in a glossary / ADR / incident,
#     and the marker itself lists every retired name by definition
#   - only ADDED lines are ever scanned. Scanning whole files would block every commit that
#     touches a file with pre-existing residue, whose cheapest escapes are an out-of-lane
#     mass rename or deleting the marker — i.e. the gate would manufacture its own bypass.

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"
LIB="$(cd "$DIR/../../hooks" && pwd)/lib"
source "$LIB/commit-files.sh"
source "$LIB/retired-terms.sh"

mkrepo() {
  local tmp; tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  REPO="$(git -C "$tmp" rev-parse --show-toplevel)"
  git -C "$REPO" config user.email t@t.test
  git -C "$REPO" config user.name tester
  mkdir -p "$REPO/.bootstrap"
}
marker() { printf '%s\n' "$@" > "$REPO/.bootstrap/retired"; }

# --- retired_load ----------------------------------------------------------------------
mkrepo
marker '# a comment' '' '  typeNo | typeId | | Intent の識別子  ' 'oldFn|newFn' '   ' '#trailing'
retired_load "$REPO/.bootstrap/retired"; RC=$?
test_case "load succeeds when at least one entry parses"
assert_eq 0 "$RC"
test_case "comments, blank and whitespace-only lines are dropped"
assert_eq 2 "${#RETIRED_TERM[@]}"
test_case "fields are trimmed"
assert_eq 'typeNo' "${RETIRED_TERM[0]}"
assert_eq 'typeId' "${RETIRED_REPL[0]}"
assert_eq 'Intent の識別子' "${RETIRED_NOTE[0]}"
test_case "a term-only line is valid (replacement/scope/note all optional)"
marker 'lonely'
retired_load "$REPO/.bootstrap/retired"
assert_eq 'lonely' "${RETIRED_TERM[0]}"
assert_eq '' "${RETIRED_REPL[0]}"
assert_eq '' "${RETIRED_SCOPE[0]}"

test_case "a marker with no parseable entry returns 1 (caller falls open)"
marker '# only a comment' ''
retired_load "$REPO/.bootstrap/retired"; assert_eq 1 "$?"
test_case "an absent marker returns 1"
retired_load "$REPO/.bootstrap/nope"; assert_eq 1 "$?"

# --- retired_path_exempt ----------------------------------------------------------------
test_case "docs are exempt (a retired name legitimately appears there)"
retired_path_exempt 'docs/glossary.md'      ; assert_eq 0 "$?"
retired_path_exempt 'README.md'             ; assert_eq 0 "$?"
retired_path_exempt 'docs/decisions/0001.txt'; assert_eq 0 "$?"
retired_path_exempt 'CHANGELOG.md'          ; assert_eq 0 "$?"
test_case "the marker itself is exempt (it lists every retired name by definition)"
retired_path_exempt '.bootstrap/retired'    ; assert_eq 0 "$?"
retired_path_exempt '.bootstrap-retired'    ; assert_eq 0 "$?"
test_case "ordinary source is not exempt"
retired_path_exempt 'src/a.ts'              ; assert_eq 1 "$?"
retired_path_exempt 'tests/a.test.ts'       ; assert_eq 1 "$?"

# --- retired_path_exempt vs retired_pathspec_args: two representations, one rule -----------
# The exempt rule exists twice: as a shell predicate (the gate walks paths through it) and as
# git pathspec exclusions (the doctor's residue sweep hands the whole tree to `git grep`).
# Two representations of one rule drift, and here the drift is silent in the worst direction:
# the gate stops seeing a path while the doctor keeps counting it, so the two views of
# "residue" disagree and neither is obviously wrong. This test pins them together by running
# BOTH over the same real repo. (Found for real: a mutation that disabled retired_path_exempt
# outright left the doctor's suite green, because the sweep spelled its exclusions inline.)
mkrepo
marker 'typeNo | typeId'
mkdir -p "$REPO/src" "$REPO/docs/decisions" "$REPO/pkg/docs"
for f in src/a.ts src/README.md docs/glossary.md docs/decisions/0001.txt pkg/docs/note.ts CHANGELOG.md .bootstrap/retired; do
  mkdir -p "$REPO/$(dirname "$f")"; printf 'x typeNo x\n' > "$REPO/$f"
done
git -C "$REPO" add src docs pkg CHANGELOG.md .bootstrap >/dev/null 2>&1
git -C "$REPO" commit -qm seed
source "$LIB/retired-terms.sh"
_ps=(); while IFS= read -r _p; do _ps+=("$_p"); done < <(retired_pathspec_args)
SWEPT="$(git -C "$REPO" grep -lwF -e typeNo -- "${_ps[@]}" 2>/dev/null)"
test_case "every path the sweep reports is one the predicate does NOT exempt"
_bad=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  retired_path_exempt "$f" && _bad="$_bad $f"
done <<EOF
$SWEPT
EOF
assert_eq '' "$_bad"
test_case "and every non-exempt path with residue IS reported by the sweep (no silent gap)"
_missing=""
for f in src/a.ts pkg/docs/note.ts; do
  retired_path_exempt "$f" && continue
  case "$SWEPT" in *"$f"*) ;; *) _missing="$_missing $f" ;; esac
done
assert_eq '' "$_missing"
test_case "the shared exemptions really do cover docs / md / changelog / the marker"
assert_eq 'src/a.ts' "$SWEPT"

# --- retired_scan_line: word boundaries -------------------------------------------------
mkrepo
marker 'typeNo | typeId | | 改名 #88'
retired_load "$REPO/.bootstrap/retired"

test_case "an identifier-safe term matches on a word boundary"
assert_eq 'typeNo|typeId|改名 #88' "$(retired_scan_line 'src/a.ts' '  if (i.typeNo === null) {')"
test_case "a longer identifier that merely contains the term does NOT match"
assert_eq '' "$(retired_scan_line 'src/a.ts' 'const typeNotation = 1')"
assert_eq '' "$(retired_scan_line 'src/a.ts' 'const mytypeNo = 1')"
assert_eq '' "$(retired_scan_line 'src/a.ts' 'const typeNo_v2 = 1')"
test_case "the term at start/end of line still matches"
assert_eq 'typeNo|typeId|改名 #88' "$(retired_scan_line 'src/a.ts' 'typeNo')"
test_case "a line with no occurrence yields nothing and returns 1"
retired_scan_line 'src/a.ts' 'const ok = 1' >/dev/null; assert_eq 1 "$?"

# --- retired_scan_line: scope-glob ------------------------------------------------------
mkrepo
marker 'legacyFlag | featureFlag | src/** | src 配下だけ禁止'
retired_load "$REPO/.bootstrap/retired"
test_case "scope-glob narrows where the term is banned"
assert_eq 'legacyFlag|featureFlag|src 配下だけ禁止' "$(retired_scan_line 'src/deep/a.ts' 'legacyFlag')"
assert_eq '' "$(retired_scan_line 'vendor/a.ts' 'legacyFlag')"

# --- retired_scan_line: multibyte fallback ----------------------------------------------
mkrepo
marker '波 | (廃止) | | 段階管理は roadmap.md が正本'
retired_load "$REPO/.bootstrap/retired"
test_case "a term with non-identifier chars falls back to substring matching"
assert_eq '波|(廃止)|段階管理は roadmap.md が正本' "$(retired_scan_line 'src/a.ts' 'const 波数 = 1')"

# --- retired_added_lines_cmd ------------------------------------------------------------
mkrepo
marker 'typeNo | typeId'
mkdir -p "$REPO/src" "$REPO/docs"
printf 'const keep = i.typeNo\n' > "$REPO/src/legacy.ts"
git -C "$REPO" add -A >/dev/null; git -C "$REPO" commit -qm seed
printf 'const keep = i.typeNo\nconst fresh = 1\n' > "$REPO/src/legacy.ts"
printf 'new file with typeNo\n' > "$REPO/src/new.ts"
printf 'doc mentions typeNo\n' > "$REPO/docs/note.md"
git -C "$REPO" add src/legacy.ts src/new.ts docs/note.md

added() { ( cd "$REPO" && retired_added_lines_cmd "$1" ) | paste -sd'~' -; }

test_case "only ADDED lines of the commit are emitted, never pre-existing ones"
assert_eq 'src/legacy.ts	const fresh = 1~src/new.ts	new file with typeNo' "$(added 'git commit -m x')"
test_case "the +++ header line is never emitted as content"
case "$(added 'git commit -m x')" in *'+++'*) assert_eq 'no-+++' 'saw +++' ;; *) assert_eq ok ok ;; esac
test_case "exempt paths are not scanned at all"
case "$(added 'git commit -m x')" in *'docs/note.md'*) assert_eq 'no-docs' 'saw docs' ;; *) assert_eq ok ok ;; esac

printf 'const keep = i.typeNo\nconst fresh = 1\nconst unstaged = 2\n' > "$REPO/src/legacy.ts"
test_case "a plain commit does NOT see the unstaged tracked change"
case "$(added 'git commit -m x')" in *unstaged*) assert_eq 'no-unstaged' 'saw unstaged' ;; *) assert_eq ok ok ;; esac
test_case "git commit -a DOES see the unstaged tracked change"
case "$(added 'git commit -am x')" in *unstaged*) assert_eq ok ok ;; *) assert_eq 'saw unstaged' 'no-unstaged' ;; esac

# --- retired_added_lines_range (the CI net path) -----------------------------------------
mkrepo
marker 'typeNo | typeId'
mkdir -p "$REPO/src"
printf 'const keep = i.typeNo\n' > "$REPO/src/legacy.ts"
git -C "$REPO" add -A >/dev/null; git -C "$REPO" commit -qm seed
BASE="$(git -C "$REPO" rev-parse HEAD)"
printf 'const keep = i.typeNo\nconst added = i.typeNo\n' > "$REPO/src/legacy.ts"
git -C "$REPO" add -A >/dev/null; git -C "$REPO" commit -qm change
test_case "range mode emits only lines added since base"
assert_eq 'src/legacy.ts	const added = i.typeNo' "$( ( cd "$REPO" && retired_added_lines_range "$BASE" ) )"

# --- retired_scan_stream: end to end -----------------------------------------------------
mkrepo
marker 'typeNo | typeId | | 改名 #88'
retired_load "$REPO/.bootstrap/retired"
test_case "the stream scanner reports rel|term|replacement|note|line"
assert_eq 'src/a.ts|typeNo|typeId|改名 #88|const x = i.typeNo' \
  "$(printf 'src/a.ts\tconst x = i.typeNo\n' | retired_scan_stream)"
test_case "a clean stream yields nothing and returns 1"
printf 'src/a.ts\tconst x = i.typeId\n' | retired_scan_stream >/dev/null; assert_eq 1 "$?"

# --- the rename itself must not be blocked -----------------------------------------------
mkrepo
marker 'typeNo | typeId'
mkdir -p "$REPO/src"
printf 'const x = i.typeNo\n' > "$REPO/src/a.ts"
git -C "$REPO" add -A >/dev/null; git -C "$REPO" commit -qm seed
printf 'const x = i.typeId\n' > "$REPO/src/a.ts"      # performing the rename
git -C "$REPO" add src/a.ts
test_case "the rename commit itself is clean (the retired name is only REMOVED)"
retired_load "$REPO/.bootstrap/retired"
( cd "$REPO" && retired_added_lines_cmd 'git commit -m rename' | retired_scan_stream ) >/dev/null
assert_eq 1 "$?"

finish
