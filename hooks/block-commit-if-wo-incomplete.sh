#!/usr/bin/env bash
# Hook — PreToolUse on Bash. The completeness gate at the moment of ORDERING.
#
# 背景: 上流工程 (要件・設計・計画) をこのプラグインに統合するにあたり、前身 2 実装
# (upstream-process / kanban-flow) が共通して死んだ理由を潰す必要があった。両者とも
# **強制を 1 つも持たなかった** — upstream-process は「判断を検出する gate は dead code に
# なる。だから上流は hook にしない」と明示的に宣言し、その帰結として全体が advisory になり
# 忘れられた。これはこのプラグインが他所で否定している失敗モードそのものである。
#
# 原則①の分解をここに当てる: 「この仕様は正しいか」は既約な判断で強制できない。だが
# **「自律稼働の事前条件が記入済みである」という precondition は強制できる** (TDD hook が
# test の質でなく存在を強制するのと同型)。何を書けば埋まったことになるかは
# templates/docs/bootstrap/commission/wo/TEMPLATE.md が権威、判定は lib/wo.sh が単一権威。
#
# ②信号選び: 信号は prompt の語彙でも「WO を編集した」でもなく、**status: ordered の WO を
# commit する行為そのもの** = AI に仕事を渡す行為それ自身。edit 時に判定しない理由は ADR
# 0021 と同型 — PreToolUse では結果ファイル全体が存在せず、status の反転と、それを無効化する
# 節の編集が別々の Edit で来る。commit なら sed / script 経由の書き込みも同時に捕まる (ADR 0017)。
# 射程は ADR 0018 と同じく **この commit が運ぶ file** だけ (tree 全体を見ない)。
#
# fail-mode:
#   - 根拠不在 = fail-open。非 git / docs/bootstrap/commission 未採用 / commit でない /
#     draft のままの WO / この commit が WO を運ばない → 素通し。
#     **draft を止めないのが重要**: 起草はまさに思考の場で、そこを止めると「checkpoint を
#     保存するために節をノイズで埋める」誘因になり、gate が自分の bypass を作る。
#   - 解析不能 = fail-closed (parse_command 失敗時)。
#
# 読む中身は **この commit が運ぶ版** (index、`-a` なら worktree)。file 名を index から取りながら
# 中身を disk から読むと、部分 stage (`git add -p`) で「検査した中身 ≠ commit される中身」になり、
# 完全性検査が黙って fail-open する。単一権威 = lib/commit-files.sh の commit_file_content。
#
# opt-in: docs/bootstrap/commission/ が在るときだけ発火。jq 非依存。

set -u

# shellcheck source=lib/parse-command.sh
. "${BASH_SOURCE[0]%/*}/lib/parse-command.sh"
# shellcheck source=lib/git-invocation.sh
. "${BASH_SOURCE[0]%/*}/lib/git-invocation.sh"
# shellcheck source=lib/resolve-docs.sh
. "${BASH_SOURCE[0]%/*}/lib/resolve-docs.sh"
# shellcheck source=lib/commit-files.sh
. "${BASH_SOURCE[0]%/*}/lib/commit-files.sh"
# shellcheck source=lib/wo.sh
. "${BASH_SOURCE[0]%/*}/lib/wo.sh"
# shellcheck source=lib/repo-top.sh
. "${BASH_SOURCE[0]%/*}/lib/repo-top.sh"

in_list() { local n="$1" x; for x in $2; do [ "$x" = "$n" ] && return 0; done; return 1; }

note() { PROBLEMS="$PROBLEMS
  [$1] $2"; }

# gate 本体 — 契約は lib/standalone.sh ヘッダ参照 (global CMD を読む / return 0=pass, 2=block)。
gate_block_commit_if_wo_incomplete() {
  local TOP CDIR CREL WORK CHARTER_REL CHARTER CHARTER_PRESENT OPEN_UNKNOWNS LEDGER_IDS
  local PROBLEMS rel WO label UNFILLED MISS_ORACLE MISS_DOD UNRESOLVED RETRY BUDGET REFS DEFERS u d

# git commit でなければ素通し (検出は単一権威 lib/git-invocation.sh、ADR 0019)。
cmd_invokes_git_subcommand "$CMD" commit || return 0

repo_top_var
TOP="$REPO_TOP"
[ -z "$TOP" ] && return 0

CDIR="$(resolve_docs_dir "$TOP" commission)"
CREL="$(resolve_docs_label "$TOP" commission)"
[ -d "$CDIR" ] || return 0   # 未採用 → 無音で素通し

# 検査する中身は **この commit が運ぶ版** (index、`-a` なら worktree) であって disk の現在形では
# ない。file 名を index から取りながら中身を worktree から読むと、`git add -p` の部分 stage や
# stage 後の編集で「検査した中身 ≠ commit される中身」になり、完全性検査が fail-open 側に倒れる。
# 解決は単一権威 lib/commit-files.sh の commit_file_content。
#
# NOTE: dispatcher (1 プロセスで gate 群を回す) の中では EXIT trap を張れない — 他 gate や
# dispatcher 自身の trap と衝突する。後始末は下の 2 つの return 経路で明示的に rm する。
# 新しい return 経路を足すときは rm -rf "$WORK" を先に置くこと。
WORK="$(mktemp -d)" || return 0

CHARTER_REL="$CREL/charter.md"
CHARTER="$WORK/charter.md"
commit_file_content "$TOP" "$CHARTER_REL" "$CMD" > "$CHARTER"
CHARTER_PRESENT=1
{ [ -s "$CHARTER" ] || [ -f "$TOP/$CHARTER_REL" ]; } || CHARTER_PRESENT=0

OPEN_UNKNOWNS="$(charter_open_unknowns "$CHARTER")"
LEDGER_IDS="$(charter_unknown_ids "$CHARTER")"

PROBLEMS=""

while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  case "$rel" in
    "$CREL"/wo/*.md) ;;
    *) continue ;;
  esac
  case "$rel" in */TEMPLATE.md) continue ;; esac

  WO="$WORK/wo.md"
  commit_file_content "$TOP" "$rel" "$CMD" > "$WO"
  [ -s "$WO" ] || continue   # 削除された WO (index にも worktree にも無い) は検査対象でない

  # 発注 (= status: ordered) だけを見る。draft / pre-review / accepted は素通し。
  [ "$(wo_frontmatter "$WO" status)" = "ordered" ] || continue

  label="$(basename "$rel")"

  # (1) 12 節すべてが記入済みか
  UNFILLED="$(wo_unfilled_sections "$WO")"
  [ -n "$UNFILLED" ] && note "$label" "未記入の節: $UNFILLED  (placeholder <...> が残っている / 節ごと無い)"

  # (2) 検算 — DoD 1 行につき外部オラクル 1 つ
  MISS_ORACLE="$(wo_dod_without_oracle "$WO")"
  [ -n "$MISS_ORACLE" ] && note "$label" "9 節に検証方法が無い DoD: $MISS_ORACLE"
  MISS_DOD="$(wo_oracle_without_dod "$WO")"
  [ -n "$MISS_DOD" ] && note "$label" "8 節に対応する DoD が無い検証方法: $MISS_DOD"

  # (3) 事前レビュー — 未実施と「指摘ゼロ」を区別する
  if [ "$(wo_prereview_rows "$WO")" = "0" ]; then
    note "$label" "12 節の事前レビューが未実施 (表に 1 行も無い)。pre-review skill を通すこと"
  else
    UNRESOLVED="$(wo_prereview_unresolved "$WO")"
    [ -n "$UNRESOLVED" ] && note "$label" "事前レビューの未決着行: $UNRESOLVED  (closed か deferred:<未決ID> のどちらかにする)"
  fi

  # (4) 停止条件の数値半分。散文の停止条件は (1) が見るが、再試行上限と予算は数値でなければ
  #     AI が従いようがない。
  RETRY="$(wo_frontmatter "$WO" retry_limit)"
  case "$RETRY" in
    ''|*[!0-9]*) note "$label" "frontmatter retry_limit が正の整数でない ('$RETRY')" ;;
    0) note "$label" "frontmatter retry_limit が 0 (= 1 度も再試行しない設定は停止条件でなく無効化)" ;;
  esac
  BUDGET="$(wo_frontmatter "$WO" budget_tokens)"
  case "$BUDGET" in
    ''|*[!0-9]*) note "$label" "frontmatter budget_tokens が正の整数でない ('$BUDGET')" ;;
  esac

  # (5) 未決台帳との突合。両前身プラグインが唯一共有していた不変条件 (「未決定は無音で埋まっては
  #     ならない」) の、機械で守れる部分。3 つに分解する:
  #       a. 4 節が参照する未決が OPEN のまま発注しない
  #       b. 4 節が参照する未決が台帳に **存在する**
  #       c. 12 節が `deferred:<id>` で決着させた先が台帳に **存在する**
  #     (c) が無いと表の「形」だけを見ることになり、`deferred:U99` のような台帳に無い ID が決着
  #     として通る = 名前をつけずに先送りする、という禁じ手そのものが素通りする。
  REFS="$(wo_referenced_unknowns "$WO")"
  DEFERS="$(wo_prereview_deferred_ids "$WO")"
  if [ -n "$REFS$DEFERS" ] && [ "$CHARTER_PRESENT" = 0 ]; then
    note "$label" "未決 ID ($REFS $DEFERS) を参照しているが $CHARTER_REL が無い → 未決台帳の検査が丸ごと効かない"
  else
    for u in $REFS; do
      if ! in_list "$u" "$LEDGER_IDS"; then
        note "$label" "4 節が未決 $u を参照しているが、$CHARTER_REL の未決台帳に $u の行が無い"
      elif in_list "$u" "$OPEN_UNKNOWNS"; then
        note "$label" "4 節が未決 $u を参照しているが、charter の未決台帳で $u はまだ OPEN"
      fi
    done
    for d in $DEFERS; do
      in_list "$d" "$LEDGER_IDS" || \
        note "$label" "12 節が deferred:$d で決着させているが、$CHARTER_REL の未決台帳に $d の行が無い (名前のつかない先送り)"
    done
  fi
done < <(commit_files_from_cmd "$CMD")

if [ -z "$PROBLEMS" ]; then
  rm -rf "$WORK"
  return 0
fi
rm -rf "$WORK"

cat >&2 <<EOF
project-bootstrap: blocking commit — 発注しようとしている作業指示書 (WO) が未完成。
$PROBLEMS

WO を status: ordered で commit する行為が「AI に仕事を渡す」行為そのもの。人間への
質疑応答を減らすほど、AI は途中で新しい情報を受け取れない — 仕様に穴があれば AI は
質問せず、もっともらしい解釈を選ぶか停止する。だから発注前に穴を閉じる。

直し方:
  1. $CREL/wo/<id>-<slug>.md の該当節を埋める (様式は同 dir の wo/TEMPLATE.md)
  2. 事前レビューが未実施なら pre-review skill をロードして仮想下流リーダーに
     仕様を壊させ、出た指摘を closed か deferred:<未決ID> に決着させる
  3. 未決 ID を参照・先送りするなら、その行を $CREL/charter.md の未決台帳に置く
     (台帳に無い ID への deferred は「名前のつかない先送り」= 決着ではない)
  4. まだ発注できる状態でないなら frontmatter を status: draft に戻す
     (draft はこの gate の対象外 — 起草そのものは止めない)
EOF
return 2
}

# 単体起動 (tests / vendoring 消費者) — dispatcher からは source されるので走らない。
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  # shellcheck source=lib/standalone.sh
  . "${BASH_SOURCE[0]%/*}/lib/standalone.sh"
  bootstrap_standalone_bash_gate gate_block_commit_if_wo_incomplete
fi
