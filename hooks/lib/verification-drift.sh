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
# AXIS 2 — async / silent-skip blind spot (D4 / ADR 0007 amendment). A DISTINCT advisory
# that fires on a POPULATED plan (NOT behind the empty-plan early-return): when the plan has
# >=1 kind=async row but NO kind=monitor row carrying a REAL oracle (field-4 != n/a). The
# verification trap "read your own response back" was framed for SYNCHRONOUS callers only;
# async paths (a cron that filtered-and-skipped a row with no log → the reminder never sent;
# a daemon whose heartbeat was alive while its work queue stalled) have no own-response to
# read. Their oracle must be EXTERNAL (a production alert / a daily aggregate). This axis
# nudges when async work was declared but no real monitor backs it.
#   CRITICAL anti-false-fire: key ONLY on the controlled-vocab `kind` field the AI
#   deliberately set (vplan_has_kind), NEVER a prose lexicon scan — an earlier
#   skip|drop|filter scan false-fired on this repo's OWN clean plan because its DROP rows
#   contain the word "drop". Same source-face-change gate as axis 1, so it is silent on
#   docs/config-only branches. Advisory only — never exits 2.
#
# AXIS 3 — held-out / metamorphic blind spot (7th seam / ADR 0016). Same SHAPE as axis 2
# (a declared risk that is not backed by its mitigation kind): when the plan has >=1
# kind=gameable row (the author flagged a behaviour whose oracle could be satisfied by
# special-casing / hardcoding — the impl returns the expected value on the test input, hard-
# codes the example case, or edits the grader) but NO kind=metamorphic row (the mitigation
# that perturbs the input so a decided-in-advance answer breaks; a held-out oracle is the
# structural alternative, recorded as a metamorphic/PASS row once wired). The research behind
# ADR 0016: hardcoding splits into Class A (capability-limit — statically detectable, handled
# by the lint/CI secret-scan) and Class B (reward-hack test-gaming — NOT statically
# detectable; held-out tests are the empirically strongest mitigation). This axis is the
# doctor half for Class B: it makes a DECLARED gameable path with no defeater visible.
#   Same anti-false-fire discipline as axis 2: key ONLY on the controlled-vocab `kind` field
#   (vplan_has_kind), NEVER a prose lexicon scan — a behaviour/note that merely contains the
#   word "hardcode"/"game" must not fire. DECLARED-risk trigger (not a co-authored-delta auto-
#   fire) BY DESIGN: TDD co-authors impl+test on every lane, so an auto-fire would bloat every
#   lane; keying on the author's `gameable` flag keeps it silent until the risk is declared
#   (ADR 0016 refines its backlog item (a) to this declared shape). Advisory only — never exit 2.
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

# _vd_has_real_monitor <plan-file> — rc 0 iff a kind=monitor data row carries a REAL oracle
# (field 4 is non-empty AND not the literal "n/a", case-folded). A placeholder monitor row
# (oracle = n/a) does NOT cover an async blind spot, so it does not count. Keyed on the
# controlled-vocab kind field (vplan_field 2), never on prose.
_vd_has_real_monitor() {
  local file="$1" line kind oracle
  [ -f "$file" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$(vplan_row_status "$line")" ] || continue
    kind="$(vplan_field "$line" 2 | tr '[:upper:]' '[:lower:]')"
    [ "$kind" = monitor ] || continue
    oracle="$(vplan_field "$line" 4 | tr '[:upper:]' '[:lower:]')"
    case "$oracle" in ''|n/a|na|none|-) continue ;; esac
    return 0
  done < "$file"
  return 1
}

# _vd_async_blindspot_block <plan-file> <branch> — echo the async advisory block (or nothing).
# Fires iff the plan has >=1 kind=async row AND no monitor row with a real oracle. The caller
# guarantees a source-face change already gated this (so docs-only branches are silent).
_vd_async_blindspot_block() {
  local plan="$1" cur="$2"
  vplan_has_kind "$plan" async || return 0           # no async work declared → nothing to say
  _vd_has_real_monitor "$plan" && return 0           # a real monitor backs it → covered
  printf 'async / scheduled な検証行があるのに、外部オラクルを持つ monitor 行がありません (silent-skip の盲点):\n'
  printf '  branch %s の plan (docs/verification/%s.md) に kind=async 行があるが、kind=monitor で\n' \
    "${cur:-?}" "$(printf '%s' "${cur:-?}" | tr '/' '_')"
  printf '  実オラクル (field-4 ≠ n/a) を持つ行が無い。cron が無音で skip した / queue が live な\n'
  printf '  heartbeat の裏で stall した、は同期の「自分の返答を読み返す」では捕まらない (async の盲点)。\n'
  cat <<'EOF'
  対処 (verification skill Step-3/6): async 行のオラクルは AI の外 = 本番計器に置く。
  kind=monitor 行を 1 つ足し、field-4 に実オラクルを書く (本番アラート / 日次集計 "CV>0 かつ
  予約=0" 等)。計器を当てないと決めたなら、その盲点を理由つきで明示的に白状する (= 無音にしない)。
EOF
  return 0
}

# _vd_heldout_blindspot_block <plan-file> <branch> — echo the held-out/metamorphic advisory
# block (or nothing). Fires iff the plan has >=1 kind=gameable row AND no kind=metamorphic
# row. Same controlled-vocab keying as the async axis (never a prose scan). The caller
# guarantees a source-face change already gated this (so docs-only branches are silent).
_vd_heldout_blindspot_block() {
  local plan="$1" cur="$2"
  vplan_has_kind "$plan" gameable || return 0        # no gameable path declared → nothing to say
  vplan_has_kind "$plan" metamorphic && return 0     # a metamorphic mitigation backs it → covered
  printf 'オラクル捕獲 (テストゲーミング) の盲点: kind=gameable 行があるのに kind=metamorphic 行がありません:\n'
  printf '  branch %s の plan (docs/verification/%s.md) に kind=gameable 行 (実装が special-case /\n' \
    "${cur:-?}" "$(printf '%s' "${cur:-?}" | tr '/' '_')"
  printf '  ハードコードで通り抜けうると宣言した行) があるが、それを崩す kind=metamorphic 行が無い。\n'
  printf '  実装がテスト入力を検知して期待値を返す・例のケースに決め打ちする、は同じ入力なら緑のまま\n'
  printf '  通る (7 番目の seam、ADR 0016)。mutation では捕まらない (special-case された実装は「強い」に見える)。\n'
  cat <<'EOF'
  対処 (verification skill Step-3): 判定を held-out oracle (実装 lane の編集面の外のテストで採点、
  実装者が触れない) にするか、kind=metamorphic 行を 1 つ足す (入力を摂動 → 決め打ちは壊れる)。
  どちらも当てないと決めたなら、その盲点を理由つきで明示する (= 無音にしない)。
EOF
  return 0
}

# verification_drift_report — see header.
verification_drift_report() {
  local dir="$1" cur plan changed count async_block heldout_block
  git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  [ -d "$dir/docs/verification" ] || return 0        # opt-in, same bar as the merge gate

  changed="$(_vd_changed_sources "$dir" | sort -u)"
  [ -n "$changed" ] || return 0                      # no unverified source work → silent

  cur="$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  plan="$(vplan_path_for_branch "$dir" "$cur")"

  # AXIS 2 (async blind spot) — a DISTINCT branch that fires on a POPULATED plan, BEFORE the
  # empty-plan early-return below. Keyed only on the controlled-vocab kind field; already
  # gated on a source-face change above (so docs-only branches stay silent). Advisory only.
  if [ -n "$plan" ] && [ -s "$plan" ]; then
    async_block="$(_vd_async_blindspot_block "$plan" "$cur")"
    [ -n "$async_block" ] && printf '%s' "$async_block"
    # AXIS 3 (held-out / metamorphic blind spot, 7th seam / ADR 0016) — same populated-plan,
    # controlled-vocab, source-face-gated shape as axis 2. Distinct advisory; both may fire.
    heldout_block="$(_vd_heldout_blindspot_block "$plan" "$cur")"
    [ -n "$heldout_block" ] && printf '%s' "$heldout_block"
  fi

  # a non-empty plan with >=1 data row means the decision is already being recorded → silent
  # (closure of an OPEN plan is the merge gate's job; surfacing ABSENCE is this lib's job).
  # NOTE: this early-return is for AXIS 1 only — AXIS 2 above already ran on the populated plan.
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
