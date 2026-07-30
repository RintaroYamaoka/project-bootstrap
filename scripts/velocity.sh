#!/usr/bin/env bash
# scripts/velocity.sh — 週次 throughput / defect rate の横断計測 CLI (Claude 非依存)。
#
# 背景: レビューを trust ladder で薄くする (= AI レビュー層に一次レビューを移す、Stage 2)
# とき、「薄くしても壊れていない」ことを判定する唯一の客観データが defect rate (= fix/revert
# 率) の推移。倍率 (throughput) も感覚でなく数字で追う。user は複数プロジェクトを並行担当
# するため、計測は単一 repo でなく **複数 repo 横断** で集計する。
#
# 限界 (採点者が 1 人の間は正直に名指しする): defect rate を測る人とレビュー帯域の律速が
# 同一人物 (= 単一 orchestrator) なので、この数字は独立統制でなく self-report に近い (=
# 自己採点の円環の throughput 版)。2 人目の独立した採点者が出るまでは「薄くして大丈夫」を
# self-report として扱い過信しない。取引を否定するのでなく限界を無音にしない (③ の自己適用)。
#
# usage: bash scripts/velocity.sh [repo ...]   (省略時 cwd)
#
# 出力 (TSV, machine-greppable):
#   <repo>\tw<weeks-ago>\t<commits>\t<merges>\t<fixrev>     # repo × 週 (直近 4 週、w0=今週)
#   TOTAL\tw<weeks-ago>\t...                                # 週ごとの横断合算
#   TOTAL\t4w\t<commits>\t<merges>\t<fixrev>\tdefect=<pct>% # 4 週合算 + defect 率
#
# 定義:
#   commits = 非 merge commit 数 / merges = merge commit 数
#   fixrev  = subject が fix:/hotfix/revert (大文字小文字無視) で始まる、または日本語の
#             defect 語 (修正 / バグ / 不具合 / 誤り — subject 中のどこでも) を含む非 merge
#             commit 数。user の repo は日本語 subject が主で、英語 prefix だけ数えると
#             defect 率が 4 倍過小になった (実測 3% vs ~12%。docs/bootstrap/incidents/
#             2026-06-11-velocity-fixrev-japanese-blind)。token は実 cohort で精度検証済み —
#             「戻す」(業務フロー語: CDへ戻す/差し戻す)、「直し」(やり直し = incident 記録語)、
#             「解消」(handoff 更新などの非 defect) は false positive を確認し不採用 (罠 4)
#   defect% = fixrev / commits (4 週合算、commits=0 なら 0%)
#
# 基準線: 旧方式 (英語 prefix のみ) で測った「11%」は無効。新方式の起点 = 2026-06-11 実測
# 12% (creative-team-app + bootstrap 横断 4w)。以後この CLI の推移で更新し、跳ねたらレビューを
# 1 段厚く戻す / 安定して下回ったら lane を上げる (trust ladder の昇降判定)。
#
# 非 git path は警告してスキップ。有効 repo が 1 つも無ければ exit 1。jq 非依存。

set -u

REPOS=("$@")
[ ${#REPOS[@]} -eq 0 ] && REPOS=("$PWD")

NOW=$(date +%s)
WEEK=604800

# 集計領域: 添字 = weeks_ago (0..3)
declare -a T_COMMITS=(0 0 0 0) T_MERGES=(0 0 0 0) T_FIXREV=(0 0 0 0)
VALID=0

for repo in "${REPOS[@]}"; do
  if ! git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "velocity: skip non-git path: $repo" >&2
    continue
  fi
  VALID=$((VALID + 1))
  declare -a R_COMMITS=(0 0 0 0) R_MERGES=(0 0 0 0) R_FIXREV=(0 0 0 0)

  # 非 merge commit: epoch + subject。`%p` の parent 解析は採らない — root commit で %p が
  # 空になると tab が collapse して field がずれる。--no-merges / --merges の 2 pass が堅牢。
  # `|| [ -n "$ct" ]` は末尾改行なしの最終行 (= 最古 commit) を read が落とすのを防ぐ。
  while IFS=$'\t' read -r ct subj || [ -n "${ct:-}" ]; do
    [ -z "${ct:-}" ] && continue
    age=$(( (NOW - ct) / WEEK ))
    { [ "$age" -lt 0 ] || [ "$age" -gt 3 ]; } && continue
    R_COMMITS[$age]=$((R_COMMITS[$age] + 1))
    if printf '%s' "$subj" | grep -qiE '^[[:space:]]*"?(fix|hotfix|revert)|修正|バグ|不具合|誤り'; then
      R_FIXREV[$age]=$((R_FIXREV[$age] + 1))
    fi
    ct=""
  done < <(git -C "$repo" log --no-merges --since="28 days ago" --pretty=format:'%ct	%s' 2>/dev/null)

  # merge commit: epoch のみ。
  while IFS= read -r ct || [ -n "${ct:-}" ]; do
    [ -z "${ct:-}" ] && continue
    age=$(( (NOW - ct) / WEEK ))
    { [ "$age" -lt 0 ] || [ "$age" -gt 3 ]; } && continue
    R_MERGES[$age]=$((R_MERGES[$age] + 1))
    ct=""
  done < <(git -C "$repo" log --merges --since="28 days ago" --pretty=format:'%ct' 2>/dev/null)

  for w in 0 1 2 3; do
    printf '%s\tw%d\t%d\t%d\t%d\n' "$repo" "$w" "${R_COMMITS[$w]}" "${R_MERGES[$w]}" "${R_FIXREV[$w]}"
    T_COMMITS[$w]=$((T_COMMITS[$w] + R_COMMITS[$w]))
    T_MERGES[$w]=$((T_MERGES[$w] + R_MERGES[$w]))
    T_FIXREV[$w]=$((T_FIXREV[$w] + R_FIXREV[$w]))
  done
done

if [ "$VALID" -eq 0 ]; then
  echo "velocity: no valid git repo among arguments" >&2
  exit 1
fi

SUM_C=0; SUM_M=0; SUM_F=0
for w in 0 1 2 3; do
  printf 'TOTAL\tw%d\t%d\t%d\t%d\n' "$w" "${T_COMMITS[$w]}" "${T_MERGES[$w]}" "${T_FIXREV[$w]}"
  SUM_C=$((SUM_C + T_COMMITS[$w]))
  SUM_M=$((SUM_M + T_MERGES[$w]))
  SUM_F=$((SUM_F + T_FIXREV[$w]))
done

PCT=0
[ "$SUM_C" -gt 0 ] && PCT=$((SUM_F * 100 / SUM_C))
printf 'TOTAL\t4w\t%d\t%d\t%d\tdefect=%d%%\n' "$SUM_C" "$SUM_M" "$SUM_F" "$PCT"
exit 0
