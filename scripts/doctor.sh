#!/usr/bin/env bash
# scripts/doctor.sh — project-bootstrap 採用状態の self-audit (Claude 非依存 CLI)。
#
# 背景: 規律 gate (TDD 先行 / 依存方向 / 並列 lane / sprint 発火 / protected push / commit test)
# は、その hook が消費先 repo で **実際に現行版で走っている** ことに全面依存する。arch は CI net
# (scripts/arch-check.sh) が後追いで拾うが、sprint 発火 gate は build *前* の分解判断なので
# commit-time / CI で後追いできず、PreToolUse hook 以外に backstop を持てない (ADR 0002)。
# つまり「採用したのに gate が届いていない」状態が無音で成立すると、誰も止められない。実際に
# 起きた: sprint flow 採用済みの repo に block-unplanned-feature-build.sh が未配備で、判断ミスを
# 止める裏が無かった (会話: 2026-06-02 / docs/incidents/2026-06-02-coverage-drift-silent)。
#
# 本 script は repo の採用状態を 1 つの verdict に判定する。SessionStart hook (session 起動時に
# 可視化) と CI template (plugin 非依存の team-wide net) の両方が同じエンジンを呼ぶ。
#
# verdict (STATUS 行 = 1 行目、machine-readable):
#   skip      — 非 git。adoption は git repo 単位なので判断基盤なし → 何もしない (fail-open)。
#   unadopted — .bootstrap-* / docs/{sprint,decisions,...} いずれも無い。導入を提案する余地。
#   declined  — unadopted だが .bootstrap-declined が在る → 提案を抑止 (nag しない)。
#   partial   — 採用済みだが整合しない。中核は vendored-coverage gap (= .claude/hooks/ で
#               vendoring しているのに採用機能に必要な hook が物理的に欠落 = propagate-ai 型の穴)。
#   ok        — 採用済み・整合。
#
# exit: ok/unadopted/declined/skip = 0、partial = 2 (CI が fail にできる契約)。
# fail-mode (memory feedback_gate_signal_and_failmode 準拠): 根拠不在 (非 git / plugin 経由で
# repo から版検証不能) は fail-open。jq 非依存。
#
# usage: bash scripts/doctor.sh [repo_root]   (省略時 cwd)

set -u

REPO="${1:-$PWD}"

# git root 解決。非 git は判断基盤が無い → skip (fail-open)。
GITTOP=""
if command -v git >/dev/null 2>&1; then
  GITTOP=$(git -C "$REPO" rev-parse --show-toplevel 2>/dev/null | tr '\\' '/' | tr -s '/')
fi
if [ -z "$GITTOP" ]; then
  echo "STATUS: skip"
  echo "non-git directory ($REPO) — adoption は git repo 単位。判断基盤なし → 何もしない。"
  exit 0
fi
REPO="$GITTOP"

have() { [ -e "$REPO/$1" ]; }

# marker 解決は単一権威 (resolve-marker.sh) に委譲 — `.bootstrap/<name>` (新) を優先し
# `.bootstrap-<name>` (旧) に fallback する。lib 不在の異常配置では旧 flat path に退避。
RESOLVER_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)/hooks/lib/resolve-marker.sh"
# shellcheck source=../hooks/lib/resolve-marker.sh
[ -f "$RESOLVER_LIB" ] && . "$RESOLVER_LIB"
marker() {
  if command -v resolve_marker >/dev/null 2>&1; then resolve_marker "$REPO" "$1"
  else printf '%s/.bootstrap-%s' "$REPO" "$1"; fi
}
have_marker() { [ -e "$(marker "$1")" ]; }
# repo 相対の表示ラベル (`.bootstrap/arch` 新 / `.bootstrap-arch` 旧 — 実際に解決したパス)。
marker_rel() { local p; p="$(marker "$1")"; printf '%s' "${p#"$REPO"/}"; }

# --- 採用 marker の検出 ---
ARCH=0; PROT=0; LINT=0; LANE=0; SPRINT=0; MEM=0; VERIFY=0
have_marker arch       && ARCH=1
have_marker protected  && PROT=1
have_marker lint       && LINT=1
have_marker lane       && LANE=1
[ -d "$REPO/docs/sprint" ] && SPRINT=1
[ -d "$REPO/docs/verification" ] && VERIFY=1
{ [ -d "$REPO/docs/decisions" ] || [ -d "$REPO/docs/handoffs" ] || [ -d "$REPO/docs/incidents" ]; } && MEM=1

ADOPTED=0
[ $((ARCH + PROT + LINT + LANE + SPRINT + VERIFY + MEM)) -gt 0 ] && ADOPTED=1

# --- unadopted 分岐 ---
if [ "$ADOPTED" = 0 ]; then
  if have .bootstrap-declined; then
    echo "STATUS: declined"
    echo "未採用だが .bootstrap-declined が在る → 導入提案を抑止 (nag しない)。"
    exit 0
  fi
  echo "STATUS: unadopted"
  cat <<'EOF'
この repo は project-bootstrap を採用していない (.bootstrap-* / docs/{sprint,decisions,handoffs,incidents} いずれも無い)。
規律 gate (TDD 先行 / 依存方向 / 並列 lane / sprint 発火 / protected push / commit test) は marker を置くまで何も効かない。

→ 導入するかを user に **一度だけ尋ねる**。勝手に採用ファイルを作らない。導入するなら最低限:
  - docs/{decisions,handoffs,incidents}/  (external memory)
  - 必要に応じ .bootstrap-arch (依存方向) / .bootstrap-protected (push 保護) / docs/sprint/ (並列開発) / .bootstrap-lint
導入を望まないと言われたら、この提案を以後黙らせるため repo root に空の .bootstrap-declined を置く。
EOF
  exit 0
fi

# --- 採用済み: 整合チェック (partial の検出) ---
ISSUES=()

# 1) 宣言したのに中身が空 = 宣言だけで何も強制しない silent no-op。
if [ "$ARCH" = 1 ] && ! grep -qE '^[[:space:]]*layer[[:space:]]' "$(marker arch)" 2>/dev/null; then
  ISSUES+=("$(marker_rel arch) は在るが layer 宣言が 1 行も無い → 依存方向 gate は実質 no-op")
fi
if [ "$PROT" = 1 ] && ! grep -qE '^[[:space:]]*[^#[:space:]]' "$(marker protected)" 2>/dev/null; then
  ISSUES+=("$(marker_rel protected) は在るが branch 行が無い → push 保護は実質 no-op")
fi
# .bootstrap-wip: 宣言が在るのに整数として解析できないと、hook 側 (resolve-wip-limit.sh) は
# 表示値ゆえ fail-open に form-aware な既定へ落ちる — が、その「落ちた」事実は宣言者に届かない。
# 判定は hook と同じエンジンを source して単一権威に保つ (lib 不在の異常配置では skip = fail-open)。
# parseability は display 文字列の一致でなく整数版 resolve_wip_limit_int の rc で見る (= 既定文言の
# 変更に結合しない。文字列一致は ADR 0006 の既定改名で一度割れた)。
WIPLIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)/hooks/lib/resolve-wip-limit.sh"
if have_marker wip && [ -f "$WIPLIB" ]; then
  # shellcheck source=../hooks/lib/resolve-wip-limit.sh
  . "$WIPLIB"
  if ! ( cd "$REPO" && resolve_wip_limit_int >/dev/null 2>&1 ); then
    ISSUES+=("$(marker_rel wip) は在るが整数が読めない → wip_limit 宣言は無音で無視され既定 (worker 3-4) 表示に落ちる (1 行目に整数のみを書く)")
  fi
fi

# 2) vendored-coverage gap (= 本 incident の中核): .claude/hooks/ で vendoring しているのに、
#    採用機能に必要な hook が物理的に欠けている。「宣言したのに gate が不在」の silent な穴。
VHOOKS="$REPO/.claude/hooks"
VENDORED=no
if [ -d "$VHOOKS" ]; then
  VENDORED=yes
  REQ=(require-test-companion.sh block-commit-if-tests-fail.sh block-add-all.sh block-dangerous-git-ops.sh block-cross-claude-wip.sh)
  [ "$SPRINT" = 1 ] && REQ+=(block-unplanned-feature-build.sh block-out-of-lane-edit.sh block-out-of-lane-commit.sh block-uniso-main-edit.sh block-unreviewed-merge.sh block-over-wip-parallel.sh)
  [ "$VERIFY" = 1 ] && REQ+=(block-merge-if-verification-unclosed.sh)
  [ "$ARCH"   = 1 ] && REQ+=(block-cross-layer-import.sh block-arch-violations.sh)
  [ "$PROT"   = 1 ] && REQ+=(block-push-to-protected.sh)
  [ "$LINT"   = 1 ] && REQ+=(block-commit-if-lint-fails.sh)
  MISSING=""
  for h in "${REQ[@]}"; do
    [ -f "$VHOOKS/$h" ] || MISSING="$MISSING $h"
  done
  if [ -n "$MISSING" ]; then
    ISSUES+=(".claude/hooks/ で vendoring しているが採用機能に必要な hook が欠落:$MISSING")
    ISSUES+=("  → 宣言したのに gate が物理的に不在 (propagate-ai 型の silent 穴)。欠落 hook を vendor し直し、.claude/settings.json に配線する。")
  fi
fi

SUM="arch=$ARCH protected=$PROT lint=$LINT lane=$LANE sprint=$SPRINT verify=$VERIFY memory=$MEM vendored=$VENDORED"

# --- action-memory registry audit (lane D2 / ADR 0010) ---
# Surface-only (never flips status / never exits 2): report whether the repo arms any
# repeat-prone action (.bootstrap-actions, opt-in) and list ORPHAN entries — an armed key
# that is NOT in the plugin's CLOSED enum, so its memo can NEVER fire (a silent dead arm).
# Also surface a repeat-action incident that has NO registered key when it is cheaply
# detectable (an incident dir tagged `repeat-action` while the registry is absent/empty):
# that is the very gap this lane closes (a fix recorded but never armed to re-surface).
# The judge is hooks/lib/action-gate.sh — same authority the injector uses, so doctor and
# the hook cannot drift on what a valid key is.
ACTIONS_LINE=""
AGLIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)/hooks/lib/action-gate.sh"
if [ -f "$AGLIB" ]; then
  # shellcheck source=../hooks/lib/action-gate.sh
  . "$AGLIB"
  ACTIONS_FILE="$(marker actions)"
  if [ -f "$ACTIONS_FILE" ]; then
    ARMED_N=$(grep -cE '^[[:space:]]*[^#[:space:]]' "$ACTIONS_FILE" 2>/dev/null || echo 0)
    ORPHANS=$(registry_orphan_keys "$REPO" 2>/dev/null | paste -sd, - )
    if [ -n "$ORPHANS" ]; then
      ACTIONS_LINE="actions: actions marker present ($ARMED_N armed) — ORPHAN keys not in the plugin enum: $ORPHANS (memo can never fire; fix the key or add it to action-gate.sh)"
    else
      ACTIONS_LINE="actions: actions marker present ($ARMED_N armed, no orphans)"
    fi
  else
    # No registry. If an incident is tagged as a repeat-prone action, the fix it records is
    # not armed to re-surface — point at the actions marker. Cheap grep over incident dirs.
    if [ -d "$REPO/docs/incidents" ] && grep -rilE 'repeat[- ]?action' "$REPO/docs/incidents" >/dev/null 2>&1; then
      ACTIONS_LINE="actions: no actions marker, but a docs/incidents entry is tagged repeat-action — arm its action-key (templates/bootstrap-actions.example) so the recorded fix re-surfaces at the action"
    fi
  fi
fi

if [ "${#ISSUES[@]}" -gt 0 ]; then
  echo "STATUS: partial"
  echo "project-bootstrap 採用済みだが整合しない点がある ($SUM):"
  for i in "${ISSUES[@]}"; do echo "  - $i"; done
  [ -n "$ACTIONS_LINE" ] && echo "  - $ACTIONS_LINE"
  if [ "$VENDORED" = no ]; then
    echo "(plugin 経由採用は plugin の install/版を repo から検証不能。team-wide に強制するなら .claude/hooks/ への vendoring か templates/ci/bootstrap-doctor.yml を CI に置く)"
  fi
  exit 2
fi

echo "STATUS: ok"
echo "project-bootstrap 採用済み・整合 ($SUM)。"
[ -n "$ACTIONS_LINE" ] && echo "  - $ACTIONS_LINE"
if [ "$VENDORED" = no ]; then
  echo "注: hook は plugin 経由 (repo に vendoring 無し)。plugin が未 install / 旧版の環境では gate が静かに効かない —"
  echo "    team-wide net には .claude/hooks/ への vendoring か templates/ci/bootstrap-doctor.yml (plugin 非依存) を検討。"
fi
exit 0
