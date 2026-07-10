#!/usr/bin/env bash
# Hook — PreToolUse on Bash for `git merge`
# 統合の入口で「動作テスト計画 (verification plan) が閉じている」ことを fail-closed に強制する。
#
# 背景 (docs/decisions/0007 + appo-followup dogfood): コードレベルのバグは TDD hook + レビューで
# 潰れた。残余リスクは継ぎ目 (cross-repo 契約 / 要件 / 「実物を見ずの完了」/ 環境) に移動した。
# それらは repo 内 unit test の射程外で、しかも緑の unit test が誤った契約を固定して false
# confidence を配る (mood incident: zod min(1) の test は緑のまま実予約を全 reject)。防御は
# verification を「永続・共有・fail-closed な成果物」にし、その成果物が閉じていることを統合の
# precondition にすること。「良いテスト」は強制できないが「計画の存在と未解決行ゼロ」は強制できる
# (TDD hook が test の存在を、review gate が verdict の存在を強制するのと同型)。
#
# 信号 = 統合行為 (= 並列 lane branch の git merge)。「どの方式で並列開発したか」に依存しないよう、
# review gate (block-unreviewed-merge) と同じ lane 集合を使う:
#   (a) 活性 board の task branch  (b) linked worktree に checkout された branch (ADR 0004)。
#
# fail-mode (memory feedback_gate_signal_and_failmode 準拠):
#   - コマンド解析不能 = fail-closed (parse-command の契約。bypass 防止)
#   - 根拠不在 = fail-open: 非 merge / 非 git / docs/verification/ 未採用 (= opt-in) /
#     merge 対象が lane branch でない (通常の merge を一切妨げない)
#   - 採用済みで lane branch を merge するのに計画が無い / 空 / 未解決行が残る = fail-closed
#     (= 「計画を書かない」で gate を素通りさせない。強制したい判定を advisory に逃さない)
#
# 射程の境界 (ADR 0007 で明示): この gate は統合 (= lane branch の merge) を信号にするので、
# branch を切らない逐次作業は捕まえない。そこは `verification` skill (plan 時の precondition) と
# doctor (配備可視化) が担う。trunk への全変更を縛る universal 版は push-to-protected への拡張余地。
#
# ── cross-repo contract drift (D3・ADR 0011・fail-CLOSED 拡張) ───────────────────────
# 既存 plan check の後に、もう 1 軸を見る: lane branch の OWN delta (= base..lane を OFFLINE で
# 計算 — 後述) が docs/verification/contracts で宣言された local_face_glob に当たる契約 id ごとに、
#   (1) その id を参照する CLOSED な plan 行 (PASS / 理由つき DROP) を要求し、無ければ block。
#   (2) consumer 側の contract test を関所自身が実走し (detect-test-suite.sh + block-unreviewed-
#       merge.sh と同じ「関所がスイートを回す」move)、red なら block。自動で回せない時は plan 行を
#       STATUS=HUMAN にして OPEN のまま — 人間が PASS+証拠を記録するまで free-text PASS で閉じない。
# 背景 (incidents): sibling repo がフォームから 1 項目落としたのに zod 必須のままで CV 全 reject /
#   3 repo の 1 つで plan 値が変わり無音 no-op。共有スキーマの宣言も cross-repo test も無かった。
# **OFFLINE な lane delta** が肝 (critique blocker): PreToolUse merge hook 時点で HEAD = 統合先
#   (main) なので、cwd/HEAD を見る doctor の _vd_changed_sources は空集合 = gate が発火しない。
#   だから lib/cross-repo-contract.sh の branch_changed_sources が base..lane を見る (no fetch)。
# **consumer 側のみ**: 関所は sibling repo を読まない / diff しない (peer は人間の手掛かり)。
#   sibling checkout が無いマシンでも誤発火しない。下流専用変更は本 repo に lane branch を生まない
#   = 構造的に到達不能 (governing 側 no-op。「カバー」と無音で匂わせない)。
# fail-OPEN (no-grounds): docs/verification 未採用 / contracts 不在・契約ゼロ / delta が宣言面に
#   当たらない / lane branch でない / sibling 未読。← 通常 merge も非対象 lane も決して妨げない。
#
# bypass: 例外的に必要なら /permissions で本 hook を一時 deny。

set -u

INPUT=$(cat)
# shellcheck source=lib/parse-command.sh
. "$(dirname "$0")/lib/parse-command.sh"
if ! CMD="$(printf '%s' "$INPUT" | parse_command)"; then
  echo "project-bootstrap: could not parse the tool command from hook input — blocking to fail safe (fail-closed). If this is a false positive, disable this hook via /permissions." >&2
  exit 2
fi

[ -z "$CMD" ] && exit 0

# git merge でなければ素通し (path-prefixed git も含め共有エンジンで判定)。
# shellcheck source=lib/merge-targets.sh
. "$(dirname "$0")/lib/merge-targets.sh"
cmd_has_git_merge "$CMD" || exit 0

# repo root を解決。非 git は根拠不在 → fail-open。
command -v git >/dev/null 2>&1 || exit 0
TOP=$(git rev-parse --show-toplevel 2>/dev/null | tr '\\' '/' | tr -s '/')
[ -z "$TOP" ] && exit 0

# opt-in: verification flow を採用した project (= docs/verification/ が在る) でのみ発火。
[ -d "$TOP/docs/verification" ] || exit 0

# 並列 lane の branch 集合 (review gate と同じ信号) は単一権威 lib/lane-set.sh で組み立てる
# (活性 board の task branch ∪ linked worktree の branch、ADR 0004。board 不在なら (a) は空)。
# shellcheck source=lib/lane-set.sh
. "$(dirname "$0")/lib/lane-set.sh"
LANE_BRANCHES=$(lane_branches "$TOP")

# lane が 1 つも無ければ判定根拠なし → fail-open (通常の merge を一切妨げない)。
[ -z "$(printf '%s' "$LANE_BRANCHES" | tr -d '[:space:]')" ] && exit 0

is_lane_branch() { lane_set_contains "$1" "$LANE_BRANCHES"; }

# merge 対象 branch を全 segment から enumerate する (review gate と同じ共有エンジン)。
# 1 つでも「計画なし / 空 / 未解決」の lane branch があれば、その branch の理由で block する。
# shellcheck source=lib/verification-plan.sh
. "$(dirname "$0")/lib/verification-plan.sh"
# shellcheck source=lib/cross-repo-contract.sh
. "$(dirname "$0")/lib/cross-repo-contract.sh"

HAS_LANE=0
NEEDS_CONTRACT_SUITE=0   # set when >=1 touched contract was acknowledged (run the suite once)
while IFS= read -r BRANCH; do
  [ -z "$BRANCH" ] && continue
  is_lane_branch "$BRANCH" || continue
  HAS_LANE=1
  PLAN="$(vplan_path_for_branch "$TOP" "$BRANCH")"

  if [ ! -s "$PLAN" ]; then
    cat >&2 <<EOF
project-bootstrap: blocking merge of "$BRANCH" — no verification plan.

並列 lane の branch を、動作テスト計画なしに統合しようとした。verification flow を採用した
repo (docs/verification/) では、統合の precondition として計画が要る。対処 (verification skill):
  1. 意図と「跨いだ境界」から検証すべき挙動を導く (実装からでなく — 実装追認テストを避ける)
  2. $PLAN に記録する。各行: STATUS | kind | behaviour | oracle | by | evidence
  3. 自動行を実行して PASS に、人間しか採点できない行は HUMAN にして実施・記録、テストしないと
     決めた行は理由つき DROP にする。OPEN 行 (TODO/FAIL/HUMAN) が残る限り統合は通らない

計画を skip したい例外時は /permissions で本 hook を一時 deny にする。
EOF
    exit 2
  fi

  ROWS="$(vplan_row_count "$PLAN")"
  if [ "$ROWS" = 0 ]; then
    cat >&2 <<EOF
project-bootstrap: blocking merge of "$BRANCH" — verification plan has no test cases.

計画ファイル ($PLAN) は在るが、データ行 (STATUS | kind | behaviour | ...) が 1 つも無い。
空の計画は「検証ゼロ」を緑に見せる儀式。検証すべき挙動を最低 1 行書く (テストしないと判断した
ものは理由つき DROP 行で明示する — 無音で省かない)。
EOF
    exit 2
  fi

  OPEN="$(vplan_open_rows "$PLAN")"
  BAD="$(vplan_bad_drops "$PLAN")"

  if [ -n "$OPEN" ] || [ -n "$BAD" ]; then
    cat >&2 <<EOF
project-bootstrap: blocking merge of "$BRANCH" — verification plan is not closed.

計画ファイル: $PLAN
EOF
    if [ -n "$OPEN" ]; then
      echo "" >&2
      echo "未解決の行 (TODO=未実施 / FAIL=失敗 / HUMAN=人間の実施待ち):" >&2
      printf '  %s\n' "$OPEN" >&2
    fi
    if [ -n "$BAD" ]; then
      echo "" >&2
      echo "理由なき DROP (テストしない判断には理由が要る — 無音カット禁止):" >&2
      printf '  %s\n' "$BAD" >&2
    fi
    cat >&2 <<'EOF'

対処: OPEN 行を PASS (オラクルで検証) / 理由つき DROP に解決してから統合する。
PASS にする前に各行へ kill-question を一度問う: 「このテストが緑のまま、ユーザーが困る
状態はありうるか?」— Yes ならオラクルが間違っている (mood の罠)。
EOF
    exit 2
  fi

  # ── D3 cross-repo contract axis (ADR 0011, fail-CLOSED) — AFTER the plan checks. ──
  # The lane's OWN delta (base..lane, OFFLINE) intersected with declared local_face globs:
  # each touched contract id must have a CLOSED plan row that REFERENCES it. A plan that is
  # generically "closed" (its rows are all PASS/reasoned-DROP) can still silently no-op a
  # cross-repo break if none of those rows acknowledge the touched contract — block on that.
  # branch_changed_sources reads refs/heads/<branch>; a phantom lane (board branch with no
  # ref) yields the empty set → this whole axis is a no-op for it (fail-open, as designed).
  while IFS= read -r CID; do
    [ -n "$CID" ] || continue
    if crc_closed_row_references_id "$PLAN" "$CID"; then
      NEEDS_CONTRACT_SUITE=1   # acknowledged → verify by RUNNING the suite (after the loop)
      continue
    fi
    cat >&2 <<EOF
project-bootstrap: blocking merge of "$BRANCH" — cross-repo contract "$CID" touched but not closed (D3, fail-closed).

この lane は docs/verification/contracts で宣言された共有 face を変更しました (契約 id: $CID)
が、$PLAN にその契約を CLOSED にした行がありません。宣言なき共有スキーマの片側変更は無音で割れます
(sibling がフォーム項目を落としたのに zod 必須のまま → CV 全 reject、の同類 — ADR 0011)。対処:
  1. consumer-driven な contract テストを起こす (オラクル = 相手 repo の実出力)。verification skill
     の「両端を握っていない境界 → 契約テスト」。plan に行を足し id を参照する: "[contract:$CID]"。
  2. 自動で回せるなら PASS に (関所が実スイートを回して裏取りします)。回せない (相手の実出力を人間が
     確認する) なら STATUS=HUMAN にし、人間が実出力で照合して PASS+証拠を記録する。free-text PASS
     では閉じません — 触れた契約は実走 or 人間の照合のどちらかでしか CLOSED にできません。
  3. テストしないと判断したなら理由つき DROP で id を参照して明示する (= 無音で省かない)。
EOF
    exit 2
  done < <(crc_touched_contract_ids "$TOP" "$BRANCH")
done < <(merge_target_branches "$CMD")

# merge 対象に並列 lane の branch が無い → 根拠不在 → fail-open。
[ "$HAS_LANE" = 0 ] && exit 0

# D3: 触れた契約が acknowledged-closed だった lane が 1 つでもあれば、関所自身が consumer 側の
# 実スイートを 1 回回して裏取りする (free-text PASS を信じない — 信号は実テストの実行結果。
# block-unreviewed-merge.sh の ADR 0005 guard 1 と同型)。runner 未検出は fail-open: その時は
# plan 行を STATUS=HUMAN にして人間が実出力で照合するのが正路 (HUMAN は OPEN なので既存 check が
# block する)。検出は commit/review gate と共有エンジン (lib/detect-test-suite.sh) で drift 防止。
if [ "$NEEDS_CONTRACT_SUITE" = 1 ]; then
  # shellcheck source=lib/detect-test-suite.sh
  . "$(dirname "$0")/lib/detect-test-suite.sh"
  if SUITE="$(cd "$TOP" && detect_test_command)"; then
    echo "project-bootstrap: running $SUITE to verify the touched cross-repo contract(s) before merge (ADR 0011)..." >&2
    if ! ( cd "$TOP" && $SUITE ) >&2; then
      cat >&2 <<EOF
project-bootstrap: blocking merge — the test suite fails (D3 cross-repo contract, fail-closed).

触れた cross-repo 契約を CLOSED と記録した行があるが、関所が実行した実スイート ($SUITE) が
fail しました。契約の PASS は「相手の実出力で裏が取れた」ことを意味すべきで、緑のスイートが
その証拠です — 落ちるスイートを free-text の PASS で踏み越えて統合することは許可しません。対処:
  1. lane で contract テストを緑にしてから re-review し、plan の行を更新する
  2. 相手 repo (consumer 側でなく peer 側) が先に変わったのが原因なら、両側を同時に整合させる
     (片側 relax の無音破壊を避ける — ADR 0011)。
EOF
      exit 2
    fi
  fi
fi
exit 0
