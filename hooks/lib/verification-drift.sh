#!/usr/bin/env bash
# Shared judge for "verification drift" — the silent state of SEQUENTIAL trunk work:
# source-face changes were made (uncommitted, or committed ahead of the main ref) on the
# current branch, but NO verification judgment was recorded for that branch. The merge gate
# (block-merge-if-verification-unclosed.sh) only fires on the merge of a LANE branch, so
# branch-less trunk work escapes it entirely — ADR 0007's acknowledged scope boundary
# (line 60: "branch を切らない逐次作業は捕まえない。そこは ... doctor (可視化) が担う ...
# universal 版は ... 本 ADR では未実装"). This lib is that doctor half: it makes the ABSENCE
# of a verification judgment visible, the way repo-drift.sh makes a stale checkout visible.
#
# VISIBILITY, not enforcement (ADR 0003 / 0007 doctrine). Whether a given change actually
# needs a behavioural test is an irreducible judgment — but "you have unverified source
# changes and have not even recorded the test/no-test decision" is a FACT that can be
# surfaced. So nothing here exits 2; it prints advisory lines the doctor injects, and is
# SILENT when there is nothing to say. The judgment the human (or AI) then records can
# legitimately be all-DROP-with-reasons — the point is to forbid SILENTLY skipping the
# decision, not to force writing a test (memory feedback_gate_signal_and_failmode: force
# the judgment's visibility, not the act).
#
# OPT-IN & OFFLINE (same bars as the merge gate + repo-drift): fires only when
# docs/verification/ is adopted, and never fetches — the committed-ahead check compares
# against the LOCAL main remote-tracking ref (drift_main_ref). A repo with no such ref
# falls back to the uncommitted set only (fail-open: under-reports, never false-alarms).
#
# SCOPE (v1): surfaces the ABSENCE of a judgment (no plan / empty plan). It does NOT flag an
# OPEN-but-existing plan on trunk — an existing non-empty plan means the decision is in
# progress, not silently skipped, and closure on the trunk path is the future push-time
# extension ADR 0007 leaves open. Also: SessionStart catches the state you OPEN INTO;
# changes made later in the same session surface on the next session (same property as
# repo-drift).
#
# Contract (takes the repo dir as $1 so the doctor audits the session cwd, not the plugin's
# own dir; pure bash + git porcelain, jq-free, no network):
#   verification_drift_report <dir>  echo the human-readable advisory block, or nothing;
#                                    return 0 always.

# Source the sibling libs this judge composes (idempotent — re-sourcing these pure-function
# libs is harmless; the doctor may also source repo-drift.sh directly).
_vd_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=source-face.sh
. "$_vd_dir/source-face.sh"
# shellcheck source=repo-drift.sh
. "$_vd_dir/repo-drift.sh"
# shellcheck source=verification-plan.sh
. "$_vd_dir/verification-plan.sh"

# _vd_changed_sources <dir> — echo each repo-relative path (one per line) that is a source
# face and part of the current branch's not-yet-on-main delta: uncommitted working-tree
# changes, plus commits ahead of the main remote-tracking ref when one resolves.
_vd_changed_sources() {
  local dir="$1" ref line p
  # (a) uncommitted (staged + unstaged + untracked) working-tree changes.
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    p="${line:3}"                                    # strip the 2 status chars + space
    case "$p" in *" -> "*) p="${p##* -> }" ;; esac   # rename record: keep the new path
    is_source_path "$p" && printf '%s\n' "$p"
  done < <(git -C "$dir" status --porcelain 2>/dev/null)
  # (b) committed ahead of the main ref — only when a baseline resolves (offline, no fetch).
  ref="$(drift_main_ref "$dir")" || return 0
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    is_source_path "$p" && printf '%s\n' "$p"
  done < <(git -C "$dir" diff --name-only "$ref..HEAD" 2>/dev/null)
}

# verification_drift_report — see header.
verification_drift_report() {
  local dir="$1" cur plan changed count
  git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  [ -d "$dir/docs/verification" ] || return 0        # opt-in, same bar as the merge gate

  changed="$(_vd_changed_sources "$dir" | sort -u)"
  [ -n "$changed" ] || return 0                      # no unverified source work → silent

  cur="$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  plan="$(vplan_path_for_branch "$dir" "$cur")"
  # a non-empty plan with >=1 data row means the decision is already being recorded → silent
  # (closure of an OPEN plan is the merge gate's job; surfacing ABSENCE is this lib's job).
  if [ -n "$plan" ] && [ -s "$plan" ] && [ "$(vplan_row_count "$plan")" != 0 ]; then
    return 0
  fi

  count="$(printf '%s\n' "$changed" | grep -c .)"
  printf '未判断の trunk source 変更 (verification の要否判断が記録されていない — 逐次作業は merge gate の射程外):\n'
  printf '  branch %s に source 変更 %s 件、だが docs/verification/%s.md に判断が無い。\n' \
    "${cur:-?}" "$count" "$(printf '%s' "${cur:-?}" | tr '/' '_')"
  printf '%s\n' "$changed" | head -3 | while IFS= read -r p; do printf '    %s\n' "$p"; done
  [ "$count" -gt 3 ] 2>/dev/null && printf '    … 他 %s 件\n' "$((count - 3))"
  cat <<'EOF'
  対処 (verification skill): 意図と跨いだ境界から検証すべき挙動を導き、各行に外部オラクルを与えて
  docs/verification/<branch>.md に記録する。テストしないと判断した挙動は理由つき DROP 行で明示する
  (= 無音で省かない)。強制ではない — 記録すべきは「テストの有無」でなく「要否の判断」そのもの。
EOF
  return 0
}
