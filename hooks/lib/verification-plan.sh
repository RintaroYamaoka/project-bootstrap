#!/usr/bin/env bash
# Single authority for the "verification plan" format — the artifact that records
# WHAT BEHAVIOUR was verified for a piece of work, derived from intent + crossed
# boundaries (NOT from the implementation). Shared by the merge gate, the doctor,
# and the `verification` skill so the format never drifts (same pattern as
# gate-entry.sh / detect-test-suite.sh / source-face.sh).
#
# Why this exists (docs/decisions/0007 + the appo-followup dogfood):
#   Code-level bugs are crushed by the TDD hook + review. The residual risk has
#   migrated to the SEAMS — cross-repo contracts, requirements, "done"-without-
#   observing, env. Those are invisible to within-repo unit tests; worse, a green
#   unit test can LOCK IN a wrong contract and hand out false confidence (the mood
#   incident: a zod `min(1)` test was green while every real booking was rejected).
#   The defence is to make verification a persistent, shared, fail-closed artifact
#   whose oracle is external to the AI, and to gate integration on it being closed.
#
# Plan file: docs/verification/<branch _-mapped>.md   (line-oriented, jq-free).
#   - `#`-led lines and blank lines are comments/ignored.
#   - a data row is pipe-delimited, leading field = STATUS:
#         STATUS | kind | behaviour | oracle | by | evidence/note
#   - STATUS vocabulary:
#         TODO  — planned, not yet run            (OPEN)
#         FAIL  — ran, failed                      (OPEN)
#         HUMAN — needs a human run/judgement      (OPEN — the irreducible oracle)
#         PASS  — verified against its oracle       (CLOSED)
#         DROP  — deliberately not tested           (CLOSED *iff* a reason is given)
#   - fail-closed bias: any unknown/typo status counts as OPEN, and a DROP without
#     a reason counts as unjustified (no silent caps — every dropped case is logged).
#
# Contract (no stdout pollution beyond the documented echoes; pure bash, BSD-safe):
#   vplan_path_for_branch <dir> <branch>
#                                -> echoes the plan path for <branch> under <dir>
#                                   (docs/verification/<branch _-mapped>.md), or "" if
#                                   <branch> is empty. Single authority for the mapping so
#                                   the merge gate and the doctor can't drift on it.
#   vplan_row_status <line>      -> echoes UPPERCASE status, or "" if not a data row
#   vplan_is_open <line>         -> rc 0 if the row is OPEN (blocks integration)
#   vplan_field <line> <n>       -> echoes the nth pipe field, trimmed
#   vplan_row_count <file>       -> echoes integer count of data rows
#   vplan_open_rows <file>       -> echoes each OPEN data row (trimmed), one per line
#   vplan_bad_drops <file>       -> echoes each DROP row missing a reason (trimmed)

# vplan_path_for_branch — see header. Maps a branch name to its plan file. The same
# derivation the merge gate used inline; factored out so the doctor reuses it verbatim
# (gate-signal drift is the silent-bypass class this repo treats as a first-class bug).
vplan_path_for_branch() {
  local dir="$1" branch="$2"
  [ -n "$branch" ] || return 0
  printf '%s/docs/verification/%s.md' "$dir" "$(printf '%s' "$branch" | tr '/' '_')"
}

# _vplan_trim — strip leading/trailing whitespace (pure bash, no sed).
_vplan_trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

vplan_row_status() {
  local line; line="$(_vplan_trim "$1")"
  case "$line" in ''|'#'*) return 0 ;; esac
  local f1="${line%%|*}"
  f1="$(_vplan_trim "$f1")"
  printf '%s' "$f1" | tr '[:lower:]' '[:upper:]'
}

vplan_is_open() {
  case "$(vplan_row_status "$1")" in
    '') return 1 ;;        # comment / blank — not a row
    PASS|DROP) return 1 ;; # the only closing statuses
    *) return 0 ;;         # TODO / FAIL / HUMAN / unknown -> OPEN (fail-closed)
  esac
}

vplan_field() {
  local line="$1" n="$2" f
  f="$(printf '%s' "$line" | cut -d'|' -f"$n")"
  _vplan_trim "$f"
}

vplan_row_count() {
  local file="$1" line n=0
  [ -f "$file" ] || { printf '0'; return 0; }
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$(vplan_row_status "$line")" ] && n=$((n + 1))
  done < "$file"
  printf '%s' "$n"
}

vplan_open_rows() {
  local file="$1" line
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    if vplan_is_open "$line"; then
      printf '%s\n' "$(_vplan_trim "$line")"
    fi
  done < "$file"
}

vplan_bad_drops() {
  local file="$1" line reason
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    [ "$(vplan_row_status "$line")" = "DROP" ] || continue
    reason="$(vplan_field "$line" 6)"
    [ -z "$reason" ] && printf '%s\n' "$(_vplan_trim "$line")"
  done < "$file"
}
