#!/usr/bin/env bash
# Single authority for the CROSS-REPO CONTRACT declaration — the registry of which
# local source faces are shared with which sibling repo, consumed by BOTH the merge gate
# (block-merge-if-verification-unclosed.sh) and the doctor (verification-drift.sh) so the
# two surfaces can never drift on what a contract is or whose delta touched it (same
# single-authority policy as verification-plan.sh / source-face.sh / merge-targets.sh).
#
# Why this exists (docs/decisions/0011 + the appo-followup dogfood):
#   The residual risk this repo keeps getting burned by lives in CROSS-REPO SEAMS, and
#   the worst property of those seams was that NOTHING DECLARED THEM. Two incidents:
#     - a sibling repo dropped a form field while this repo's zod still required it →
#       every CV was rejected (the mood incident's class). Green within-repo tests; the
#       break lived between the two repos, undeclared.
#     - a plan value changed in one of three participating repos and silently no-op'd —
#       no record said the three were even sharing a schema, so no cross-repo test ran.
#   The fix is to make the seam an OBSERVABLE FACT: a committed, per-repo declaration of
#   id | local_face_glob | peer_repo | peer_face | note. The gate then keys the
#   "you touched a shared face → run its contract test / record a HUMAN-closed row"
#   requirement on the LANE branch's OWN delta intersecting a declared glob.
#
# Declaration file: docs/verification/contracts (line-oriented, jq-free):
#   - `#`-led and blank lines are comments/ignored.
#   - a contract row is pipe-delimited:  id | local_face_glob | peer_repo | peer_face | note
#
# CONSUMER-SIDE ONLY (the deliberate fail-OPEN that keeps non-target machines quiet):
#   This lib verifies THIS repo's consumer-side judgment. It NEVER reads or diffs the
#   sibling repo — peer_repo / peer_face are human hints, not a path the gate dereferences.
#   A machine lacking the sibling checkout therefore raises no false alarm. A downstream-
#   only change (the sibling moving, this repo unchanged) produces no lane branch here, so
#   it is structurally unreachable by the gate — documented, not silently implied as covered.
#
# OFFLINE & branch-delta-correct (THE critique blocker this lib fixes):
#   branch_changed_sources computes the LANE branch's OWN delta against its merge-base with
#   the main ref, NOT the cwd/HEAD working-tree delta. During a PreToolUse `git merge` hook
#   HEAD = the merge DESTINATION (main), so the doctor's _vd_changed_sources (cwd/HEAD) is
#   empty and the gate would never fire. We must look at base..lane instead. No fetch.
#
# Contract (pure bash + git porcelain, jq-free, no network, no stdout pollution beyond the
# documented echoes):
#   crc_contracts_file <dir>            -> echo docs/verification/contracts path under <dir>
#   crc_each_contract <file>            -> echo each contract row (raw, trimmed-of-nothing),
#                                          one per line; comments/blank skipped. "" if absent.
#   crc_field <row> <n>                 -> echo the nth pipe field, trimmed
#   crc_glob_matches <relpath> <glob>   -> rc 0 if <relpath> matches the shell <glob>
#   branch_changed_sources <dir> <lane> -> echo each repo-relative SOURCE-FACE path in the
#                                          lane branch's own delta (base..lane), one per line
#   crc_touched_contract_ids <dir> <lane> -> echo the id of each declared contract whose
#                                          local_face_glob matches a path in the lane delta
#   crc_closed_row_references_id <plan> <id> -> rc 0 iff a CLOSED (PASS / reasoned DROP)
#                                          plan row carries the ANCHORED tag `[contract:<id>]`.
#                                          NOT a raw substring scan of the row (that holed the
#                                          gate: 'booking' was falsely closed by a row tagging
#                                          the superstring 'booking-payload', and 'survey' by
#                                          prose merely mentioning the word). We key ONLY on the
#                                          literal bracketed token the repo conventions — the id
#                                          is matched as a LITERAL, never a regex, never prose
#                                          (same D4 doctrine as vplan_has_kind: controlled-vocab
#                                          token, not a lexicon scan). An OPEN row carrying the
#                                          tag does NOT close it — that row already blocks via
#                                          the plan's OPEN-row check, and a touched contract may
#                                          not be silently closed by a free-text PASS the gate
#                                          did not run. The gate ALSO runs the consumer-side
#                                          suite; this only checks for the anchored ack row.

# Resolve sibling libs (idempotent — pure-function libs, re-sourcing is harmless).
_crc_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=source-face.sh
. "$_crc_dir/source-face.sh"
# shellcheck source=repo-drift.sh
. "$_crc_dir/repo-drift.sh"
# shellcheck source=verification-plan.sh
. "$_crc_dir/verification-plan.sh"

# crc_contracts_file — see header.
crc_contracts_file() {
  printf '%s/docs/verification/contracts' "$1"
}

# _crc_trim — strip leading/trailing whitespace (pure bash, no sed).
_crc_trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# crc_each_contract — echo each non-comment, non-blank line of the contracts file.
crc_each_contract() {
  local file="$1" line t
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    t="$(_crc_trim "$line")"
    case "$t" in ''|'#'*) continue ;; esac
    printf '%s\n' "$t"
  done < "$file"
}

# crc_field — echo the nth pipe-delimited field of a contract row, trimmed.
crc_field() {
  local row="$1" n="$2" f
  f="$(printf '%s' "$row" | cut -d'|' -f"$n")"
  _crc_trim "$f"
}

# crc_glob_matches <relpath> <glob> — rc 0 iff the repo-relative path matches the shell
# glob declared in the contract. `case` glob semantics: `*` does NOT stop at `/`, so a
# directory wildcard like src/api/booking/*.ts matches nested files and an extension
# wildcard like demoSiteSurvey.* matches any extension. Empty glob never matches (so a
# malformed row contributes nothing — fail-open at the consumer).
crc_glob_matches() {
  local rel="$1" glob="$2"
  [ -n "$glob" ] || return 1
  # shellcheck disable=SC2254
  case "$rel" in
    $glob) return 0 ;;
    *) return 1 ;;
  esac
}

# branch_changed_sources <dir> <lane-branch> — see header. The lane branch's OWN delta,
# computed OFFLINE: base = merge-base(lane, main-ref-or-HEAD); diff base..lane filtered to
# source faces (so doc/config/test churn on the lane never trips a contract). Echoes
# repo-relative source paths, one per line. Silent (no output, rc 0) when the lane ref or
# the base cannot be resolved — fail-open: under-reports, never false-alarms.
branch_changed_sources() {
  local dir="$1" lane="$2" ref base p
  git -C "$dir" rev-parse --verify --quiet "refs/heads/$lane^{commit}" >/dev/null 2>&1 || return 0
  # Prefer the main remote-tracking ref as the "destination" the lane diverged from; fall
  # back to HEAD (= the merge destination at PreToolUse time) when no main ref resolves.
  ref="$(drift_main_ref "$dir" 2>/dev/null)" || ref=""
  [ -n "$ref" ] || ref=HEAD
  base="$(git -C "$dir" merge-base "refs/heads/$lane" "$ref" 2>/dev/null)" || return 0
  [ -n "$base" ] || return 0
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    is_source_path "$p" && printf '%s\n' "$p"
  done < <(git -C "$dir" diff --name-only "$base..refs/heads/$lane" 2>/dev/null)
}

# crc_touched_contract_ids <dir> <lane-branch> — for each declared contract whose
# local_face_glob matches any path in the lane delta, echo its id (one per line). The
# intersection the gate keys on: a touched id requires a CLOSED+RUN contract row to merge.
# Empty output = no-grounds (gate stays fail-open). Each changed source is matched against
# every contract's glob; ids are de-duplicated in declaration order.
crc_touched_contract_ids() {
  local dir="$1" lane="$2" cf changed row id glob p seen=""
  cf="$(crc_contracts_file "$dir")"
  [ -f "$cf" ] || return 0
  changed="$(branch_changed_sources "$dir" "$lane")"
  [ -n "$changed" ] || return 0
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    id="$(crc_field "$row" 1)"
    glob="$(crc_field "$row" 2)"
    [ -n "$id" ] && [ -n "$glob" ] || continue
    case " $seen " in *" $id "*) continue ;; esac
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      if crc_glob_matches "$p" "$glob"; then
        printf '%s\n' "$id"
        seen="$seen $id"
        break
      fi
    done <<EOF
$changed
EOF
  done < <(crc_each_contract "$cf")
}

# crc_closed_row_references_id <plan-file> <id> — see header. A CLOSED row is PASS or a
# reasoned DROP; it "references" the contract iff it carries the ANCHORED tag `[contract:<id>]`
# (the repo's documented convention — written in the behaviour or note field). We match that
# LITERAL bracketed token, NOT a raw substring of the id, so:
#   - id 'booking' is NOT closed by a row tagging the superstring 'booking-payload'
#     (`[contract:booking]` ≠ `[contract:booking-payload]` — the `]` delimiter is part of the
#     needle, so the boundary is enforced for free);
#   - prose merely mentioning a common word ('survey', 'booking') never closes a contract.
# The id is treated as a LITERAL: it is folded into the `case` PATTERN with every glob
# metacharacter (* ? [ \) escaped, so an id containing such a char can neither match more
# broadly nor break the pattern (defensive — contract ids are author-chosen tokens, but the
# fail-CLOSED gate must not be widened by a stray char). Returns 1 on a missing/empty plan.
crc_closed_row_references_id() {
  local plan="$1" id="$2" line status needle pat c i
  [ -n "$id" ] || return 1
  [ -f "$plan" ] || return 1
  # Build the literal needle `[contract:<id>]` with the id's glob metacharacters escaped so
  # the `case` pattern matches it verbatim (no regex/glob injection through the id).
  pat=""
  i=0
  while [ "$i" -lt "${#id}" ]; do
    c="${id:i:1}"
    case "$c" in
      '*'|'?'|'['|']'|'\') pat="$pat\\$c" ;;
      *) pat="$pat$c" ;;
    esac
    i=$((i + 1))
  done
  # The surrounding brackets must be LITERAL, not a `case` bracket-expression: escape them
  # (`\[ ... \]`) so the pattern matches the verbatim string `[contract:<id>]`.
  needle="*\\[contract:$pat\\]*"
  while IFS= read -r line || [ -n "$line" ]; do
    status="$(vplan_row_status "$line")"
    case "$status" in PASS|DROP) ;; *) continue ;; esac
    # shellcheck disable=SC2254
    case "$line" in $needle) return 0 ;; esac
  done < "$plan"
  return 1
}
