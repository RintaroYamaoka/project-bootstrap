#!/usr/bin/env bash
# wo-metrics.sh — 上流 (作業指示書) の品質を、下流の実測で測る。
#
# 原則④「計測つきの取引」の上流版。velocity.sh が「レビューを薄くしてよいか」を defect rate
# で判定するのと同じ立て付けで、ここは **「この作業指示書は良かったか」を、実装側で何が起きたか
# で判定する**。
#
# なぜこれが要るか (前身プラグインの敗因):
#   kanban-flow は自分の設計文書に「kanban-flow の失敗は判断ミスであり、機械的には検出できない」
#   と書き、そこで自己改善ループを諦めた。だが上流の曖昧さは消えるのではなく **下流に移動する** —
#   エスカレーション・再試行・差し戻し・予算超過として必ず観測される。観測できるなら測れるし、
#   測れるならテンプレートのどの節が効いていないかが勘でなくデータで分かる。
#
# 最重要の出力は最後の「節別エスカレーション」表。「AI が人間を呼んだとき、その穴は WO の
# 何節にあったか」の集計であり、**事前条件テンプレートのどこが薄いか**を直接指す。
#
# 入力: docs/bootstrap/commission/metrics.tsv (accept skill が検収のたび 1 行追記する)
#   列 (TAB 区切り):
#     1 wo_id  2 slug  3 ordered(YYYY-MM-DD)  4 accepted(YYYY-MM-DD)  5 retries
#     6 escalations  7 rejections  8 budget_tokens  9 actual_tokens
#     10 escalation_sections (穴があった WO 節番号の "," 連結。無ければ "-")
#   `#` 始まりはコメント。
#
# 使い方: scripts/wo-metrics.sh [repo ...]   (既定は cwd)
# AI 非依存。pure bash + awk、jq 非依存。

set -u

repos=("$@")
[ ${#repos[@]} -eq 0 ] && repos=(".")

for repo in "${repos[@]}"; do
  top=$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)
  [ -z "$top" ] && { echo "skip: $repo (not a git repo)"; continue; }

  tsv=""
  for cand in "$top/docs/bootstrap/commission/metrics.tsv" "$top/docs/commission/metrics.tsv"; do
    [ -f "$cand" ] && { tsv="$cand"; break; }
  done
  if [ -z "$tsv" ]; then
    echo "skip: $(basename "$top") (commission 未採用、または検収実績がまだ 0 件)"
    continue
  fi

  echo "=== $(basename "$top") — 作業指示書の実績 ($tsv) ==="
  awk -F'\t' '
    function d2n(s,   a) { if (s !~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/) return -1
                           split(s, a, "-"); return a[1]*372 + a[2]*31 + a[3] }
    BEGIN {
      name[1]="目的"; name[2]="作業範囲"; name[3]="変更禁止範囲"; name[4]="守るべき既存条件"
      name[5]="優先順位"; name[6]="例外時の判断方法"; name[7]="継ぎ目"; name[8]="完了条件(DoD)"
      name[9]="検証方法"; name[10]="停止条件"; name[11]="決めてよい/いけない"; name[12]="事前レビュー"
    }
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    {
      n++
      retries      += $5 + 0
      esc          += $6 + 0
      rej          += $7 + 0
      budget       += $8 + 0
      actual       += $9 + 0
      if ($6 + 0 > 0) with_esc++
      if ($7 + 0 > 0) with_rej++
      if ($8 + 0 > 0 && $9 + 0 > $8 + 0) over++
      o = d2n($3); a = d2n($4)
      if (o >= 0 && a >= 0) { lead += (a - o); leadn++ }
      if ($10 != "" && $10 != "-") {
        m = split($10, secs, ",")
        for (i = 1; i <= m; i++) { gsub(/[^0-9]/, "", secs[i]); if (secs[i] != "") sec[secs[i]]++ }
      }
      worst[$1] = $6 + 0
      slug[$1] = $2
    }
    END {
      if (n == 0) { print "  実績行なし"; exit }
      printf "  検収済み WO            : %d 件\n", n
      printf "  エスカレーション       : 計 %d 回 / %d 件の WO で発生 (%.0f%%)\n", esc, with_esc, with_esc * 100 / n
      printf "  差し戻し               : 計 %d 回 / %d 件の WO で発生 (%.0f%%)\n", rej, with_rej, with_rej * 100 / n
      printf "  再試行                 : 計 %d 回 (WO あたり %.1f)\n", retries, retries / n
      if (budget > 0)
        printf "  トークン               : 見積 %d / 実測 %d (%.0f%%)  — 予算超過 %d 件\n", budget, actual, actual * 100 / budget, over
      if (leadn > 0)
        printf "  発注→検収のリードタイム: 平均 %.1f 日 (%d 件で計測)\n", lead / leadn, leadn

      print ""
      print "  節別エスカレーション (AI が止まったとき、穴は WO の何節にあったか):"
      any = 0
      for (s = 1; s <= 12; s++) if (sec[s] > 0) { printf "    %2d 節 %-24s : %d 回\n", s, name[s], sec[s]; any = 1 }
      if (!any) print "    記録なし"
      print ""
      print "  読み方: 特定の節に偏るなら、その節のテンプレート文言か記入の慣行が弱い。"
      print "          偏らず全体に散るなら、粒度が大きすぎる (WO を小さく割る) 可能性が高い。"
      print "          エスカレーション 0 が続くなら、事前条件が過剰で発注コストを払いすぎている"
      print "          可能性もある — 0 は必ずしも良い値ではない。"
    }
  ' "$tsv"
  echo ""
done

cat <<'EOF'
注意 (velocity.sh と同じ限界を明示する): 採点者と律速が同一人物の間、この数値は
self-report に近い。「エスカレーションを呼ばなかった」は「穴が無かった」とは限らず、
「AI が勝手に解釈して進んだ」場合も 0 になる。検収 (accept skill) の [ズレ] 判定と
突き合わせて初めて意味を持つ。2 人目の独立採点者が出るまで過信しない。
EOF
