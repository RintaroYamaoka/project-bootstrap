#!/usr/bin/env bash
# Shared engine: "did this change newly introduce a RETIRED name?"
#
# WHY this exists (the incident): in ai-reception, `Intent.typeNo` (number) was renamed to
# `typeId` (string) in #88. A DIFFERENT PR merged 1h12m later still referenced `i.typeNo` —
# the author had no way to know the rename had happened. `Intent` has no `typeNo`, so the
# expression was permanently `undefined`, `undefined === null` is false, and a test UI showed
# `#undefined` for three days with no error anywhere. A rename cannot be policed by the
# renaming PR's own self-report: whoever writes code AFTER the rename does not know there is
# anything to grep for. So the retired name has to be REGISTERED once and checked by an
# independent, always-on mechanism.
#
# WHY the signal is the commit's ADDED LINES, not the tree (the load-bearing decision):
# scanning whole files would block every commit that merely touches a file carrying
# pre-existing residue. The blocked actor's cheapest ways out are then (a) leave their lane
# and mass-rename, or (b) delete the marker line — i.e. the gate would manufacture its own
# bypass (memory feedback_gate_signal_and_failmode: 塞ぐ と 塞がれても困らなくする は対で設計する).
# A commit is answerable for what it NEWLY introduces and nothing else. This is ADR 0018's
# rule ("the signal is this commit, not the tree") applied to names instead of lint. The
# accumulated residue is real but is a DIFFERENT job: scripts/doctor.sh sweeps it and reports
# a count, and never blocks (close-card vs audit, split inside one plugin).
#
# WHY commit-time only, with no edit-time twin (unlike arch, which gates both): "was this
# line ADDED" is not computable at PreToolUse. A retired name in `new_string` may be residue
# carried through an unrelated rewrite, and the rename operation itself puts the retired name
# in `old_string`. An edit-time gate would therefore block the very rename it wants. The
# commit chokepoint also catches sed/formatter/script writes for free (ADR 0017).
#
# WHY matching is plugin-owned and regex-free: consumers declare only literal terms. Letting
# a marker line carry its own regex would re-import the greedy-matcher bug class that
# merge-targets.sh / protected-branch.sh / action-gate.sh were each written to kill.
#
# Marker (opt-in by PRESENCE, resolved by lib/resolve-marker.sh):
#   <retired-term> | <replacement> | <scope-glob> | <note>
# Only the term is required. `#` comments and blank lines ignored; every field trimmed.
# No date column: git already records when the line landed, and duplicating a fact git owns
# is the authority-splitting failure this plugin names elsewhere.
#
# Pure bash, jq-free, no grep forks in the hot loop.

# Loaded entries. Parallel arrays (bash 3.2-safe; no associative arrays — Git Bash / macOS).
RETIRED_TERM=()
RETIRED_REPL=()
RETIRED_SCOPE=()
RETIRED_NOTE=()

# _retired_trim <string> — strip leading and trailing whitespace.
_retired_trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# retired_load <marker-path>
#   Populate the arrays from the marker.
#   return 0 = at least one entry parsed (the mechanism is live)
#   return 1 = absent / empty / comments only  => the CALLER FAILS OPEN. A marker with no
#              parseable entry is a declared no-op; scripts/doctor.sh reports that separately
#              so "declared but enforcing nothing" is not silent.
retired_load() {
  local file="$1" line term repl scope note
  RETIRED_TERM=(); RETIRED_REPL=(); RETIRED_SCOPE=(); RETIRED_NOTE=()
  [ -f "$file" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    line="$(_retired_trim "$line")"
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    term="$(_retired_trim "${line%%|*}")"
    [ -z "$term" ] && continue
    repl=""; scope=""; note=""
    if [ "$line" != "${line#*|}" ]; then
      line="${line#*|}"
      repl="$(_retired_trim "${line%%|*}")"
      if [ "$line" != "${line#*|}" ]; then
        line="${line#*|}"
        scope="$(_retired_trim "${line%%|*}")"
        if [ "$line" != "${line#*|}" ]; then
          note="$(_retired_trim "${line#*|}")"
        fi
      fi
    fi
    RETIRED_TERM+=("$term")
    RETIRED_REPL+=("$repl")
    RETIRED_SCOPE+=("$scope")
    RETIRED_NOTE+=("$note")
  done < "$file"
  [ "${#RETIRED_TERM[@]}" -gt 0 ]
}

# retired_path_exempt <repo-relative-path>
#   return 0 = never scan this path.
#   Docs are exempt because a retired name legitimately appears in a glossary's deprecation
#   table, an ADR, an incident record or a changelog — those are exactly the places that must
#   keep naming the old thing. The marker itself is exempt because it lists every retired
#   name by definition, so without this the gate would block its own registration.
retired_path_exempt() {
  case "$1" in
    *.md) return 0 ;;
    docs/*|*/docs/*) return 0 ;;
    CHANGELOG*|*/CHANGELOG*) return 0 ;;
    .bootstrap/retired|*/.bootstrap/retired|.bootstrap-retired|*/.bootstrap-retired) return 0 ;;
  esac
  return 1
}

# retired_pathspec_args — the SAME exemptions expressed as git pathspec exclusions, one per
#   line, for callers that hand the whole tree to `git grep` instead of walking paths through
#   retired_path_exempt (scripts/doctor.sh's residue sweep).
#
#   Why this lives here rather than inline at the call site: it is the second representation
#   of one rule, and a second representation kept somewhere else drifts. This was not
#   hypothetical — the first version of the sweep spelled the exclusions inline, and a
#   mutation that disabled retired_path_exempt entirely left the doctor's tests GREEN. The
#   gate and the sweep must exempt the same things or the two views of "residue" disagree.
retired_pathspec_args() {
  printf '%s\n' ':!*.md' ':!docs/**' ':!*/docs/**' ':!CHANGELOG*' ':!*/CHANGELOG*' \
                ':!.bootstrap/retired' ':!.bootstrap-retired'
}

# _retired_scope_ok <scope-glob> <rel> — empty scope = whole repo.
#   Glob semantics match lib/lane-match.sh deliberately: bash `[[ == ]]` globbing, where `*`
#   crosses `/`, so both `src/*` and `src/**` reach nested paths. Consumers already learned
#   that convention from `.bootstrap/lane`; a second, subtly different one would be a trap.
_retired_scope_ok() {
  local pat="$1" rel="$2"
  [ -z "$pat" ] && return 0
  # shellcheck disable=SC2053
  [[ "$rel" == $pat ]]
}

# _retired_hit <line> <term>
#   return 0 = <term> occurs in <line> as a whole identifier.
#   An identifier-safe term (only [A-Za-z0-9_]) is anchored on both sides so `typeNo` hits
#   `i.typeNo` but never `typeNotation` / `mytypeNo` / `typeNo_v2`. A term containing anything
#   else (a dotted path, or any multibyte word — Japanese has no word boundary a byte-oriented
#   anchor can find) falls back to a plain substring test. DOCUMENTED LIMIT: the fallback
#   over-matches, e.g. a retired `波` also hits `波数`. Terms that need precision should be
#   registered in their identifier form.
_retired_hit() {
  local line="$1" term="$2" rest="$1" pre before after
  case "$term" in
    *[!A-Za-z0-9_]*)
      case "$line" in *"$term"*) return 0 ;; *) return 1 ;; esac ;;
  esac
  while [ "$rest" != "${rest#*"$term"}" ]; do
    pre="${rest%%"$term"*}"
    rest="${rest#*"$term"}"
    before="${pre: -1}"
    after="${rest:0:1}"
    case "$before" in [A-Za-z0-9_]) continue ;; esac
    case "$after"  in [A-Za-z0-9_]) continue ;; esac
    return 0
  done
  return 1
}

# retired_scan_line <repo-relative-path> <line>
#   stdout = `<term>|<replacement>|<note>` for every loaded entry that hits, one per line.
#   return 0 = at least one hit. Requires a prior successful retired_load.
retired_scan_line() {
  local rel="$1" line="$2" i hit=1
  for i in "${!RETIRED_TERM[@]}"; do
    _retired_scope_ok "${RETIRED_SCOPE[$i]}" "$rel" || continue
    _retired_hit "$line" "${RETIRED_TERM[$i]}" || continue
    printf '%s|%s|%s\n' "${RETIRED_TERM[$i]}" "${RETIRED_REPL[$i]}" "${RETIRED_NOTE[$i]}"
    hit=0
  done
  return $hit
}

# _retired_emit_added <diff-producing-command...> — read a `-U0` diff on stdin for ONE file
# and emit `<rel>\t<added-line>`. `+++` is dropped: it is the header naming the file, not
# content, and it always carries the path (so a retired name in a PATH would false-positive).
_retired_emit_added() {
  local rel="$1" line
  while IFS= read -r line; do
    case "$line" in
      '+++'*) continue ;;
      '+'*) printf '%s\t%s\n' "$rel" "${line#+}" ;;
    esac
  done
}

# retired_added_lines_cmd <git-commit-command>
#   stdout = `<rel>\t<added-line>` for every non-exempt file this commit will carry.
#   Run with cwd inside the repo. The staged-vs-HEAD choice is delegated to
#   commit_files_from_cmd / commit_stages_all (lib/commit-files.sh) so the `-a` semantics
#   cannot drift from the lane and lint gates.
retired_added_lines_cmd() {
  local cmd="$1" f base
  if commit_stages_all "$cmd"; then base="HEAD"; else base="--cached"; fi
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    retired_path_exempt "$f" && continue
    git diff "$base" -U0 -- "$f" 2>/dev/null | _retired_emit_added "$f"
  done <<EOF
$(commit_files_from_cmd "$cmd")
EOF
}

# retired_added_lines_range <base-ref>
#   The CI-net twin: `<rel>\t<added-line>` for every non-exempt file changed since <base-ref>.
#   Used by scripts/retired-check.sh on a PR (`origin/<base>...HEAD`), where there is no index
#   to read. Same emit path, so the hook and the CI net cannot disagree about what "added" means.
retired_added_lines_range() {
  local base="$1" f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    retired_path_exempt "$f" && continue
    git diff "$base" -U0 -- "$f" 2>/dev/null | _retired_emit_added "$f"
  done < <(git diff --name-only "$base" 2>/dev/null)
}

# retired_scan_stream
#   stdin  = `<rel>\t<added-line>` (from either added-lines producer)
#   stdout = `<rel>|<term>|<replacement>|<note>|<line>` per violation
#   return 0 = at least one violation. Requires a prior successful retired_load.
retired_scan_stream() {
  local rec rel line found=1 hit
  while IFS= read -r rec; do
    rel="${rec%%$'\t'*}"
    line="${rec#*$'\t'}"
    while IFS= read -r hit; do
      [ -n "$hit" ] || continue
      printf '%s|%s|%s\n' "$rel" "$hit" "$line"
      found=0
    done < <(retired_scan_line "$rel" "$line")
  done
  return $found
}
