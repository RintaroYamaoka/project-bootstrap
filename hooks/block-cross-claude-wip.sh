#!/usr/bin/env bash
# Hook E — PreToolUse on Bash for `git commit`
# 並列 Claude / 別ターミナル の WIP を commit に巻き込む事故を構造的に block する。
#
# 仕組み (信号 = 「他 session が編集したか」。「file 編集ツールで触ったか」ではない):
#   1. 現 session の transcript から Edit/Write/MultiEdit/NotebookEdit の file_path を抽出
#      = "self-edited set" (= 必ず自分のものとして block 対象から除外)
#   2. 同一 projects dir の *他* session の transcript (= sibling) から同様に file_path を抽出
#      = "foreign-edited set"。projects dir の hash は cwd 由来なので、同一 dir の sibling は
#      「同一 working tree (= 共有 .git/index) を共有する別 session」を意味する。worktree 隔離下
#      では別 session は別 dir に入り sibling に現れない (= 誤 block しない)。
#   2b. 現 session の transcript から `git add <path>` の path を抽出 = "self-staged set"
#      (= 自分で名指しして index に入れた file。bulk staging は path を名指ししないので入らない)
#   3. staged file のうち、self-edited / self-staged に無く foreign-edited に*ある* file だけを
#      intruder として exit 2 で block。他 session の編集証拠が無い file は素通し (= fail-open)。
#
# なぜこの設計か (旧実装のバグ修正):
#   旧実装は「self-edited set に無ければ intruder」で、npm install (package-lock.json) /
#   generator / sed -i / cp / mv 等、Bash 経由で当 session が正規に生成・変更した file を全て
#   誤検知していた (Bash は file_path を transcript に残さないため不可視)。誤検知は
#   「lockfile を gitignore」「migration を除外」等の有害な回避策や hook 無効化を誘発し、
#   本来防ぎたい巻き込みすら防げなくなる。そこで信号を「他 session が編集した証拠」に反転し、
#   positive evidence がある時だけ block する (= 共有 index 事故の典型のみを撃つ)。
#
# Claude Code は hook input JSON に session_id / transcript_path / cwd / tool_name / tool_input を渡す。
# 公式 docs: https://code.claude.com/docs/en/hooks
#
# fail-open / fail-closed の方針 (= 本 plugin 既定の原則に整合):
#   - コマンド解析不能時 → fail-closed (= block。「何の op か理解できない」は bypass 防止)
#   - 根拠不在時 (transcript 不在 / sibling 不在 / 他 session の編集証拠なし) → fail-open
#     (= 素通し。.bootstrap-{protected,arch,lane} 不在時の素通しと同じ「根拠が無ければ通す」)
#
# bypass:
#   - 意図的に他 session の作業も commit したい場合は /permissions で本 hook を一時 deny
#   - sibling の鮮度窓は BOOTSTRAP_WIP_WINDOW_HOURS (default 24h、0 で無効化 = 全 sibling 対象)

set -u

# shellcheck source=lib/parse-command.sh
. "${BASH_SOURCE[0]%/*}/lib/parse-command.sh"
# git commit 検出は単一権威 lib/git-invocation.sh (path-prefixed git / git グローバル
# オプション形も捕まえる — 旧 regex はどちらも素通りさせた。ADR 0019)。
# shellcheck source=lib/git-invocation.sh
. "${BASH_SOURCE[0]%/*}/lib/git-invocation.sh"
# shellcheck source=lib/repo-top.sh
. "${BASH_SOURCE[0]%/*}/lib/repo-top.sh"

# transcript から Edit / Write / MultiEdit / NotebookEdit の file_path / notebook_path を抽出。
# JSONL の各行から "file_path": "..." / "notebook_path": "..." を grep。
# Bash tool の command は file_path を残さないため、ここには現れない (= 旧実装の誤検知源だった
# が、新実装は self-edited に「無い」ことを罪としないので問題にならない)。
extract_edited() {
  grep -oE '"(file_path|notebook_path)"[[:space:]]*:[[:space:]]*"[^"]*"' "$1" 2>/dev/null \
    | sed 's/.*:[[:space:]]*"//; s/"$//'
}

# transcript から「当 session が path を名指しで stage した」証跡を抜く。
# 巻き込み事故の本体は「自分が選んでいない file が index に居る」ことなので、path を名指しで
# `git add` したのは意思であって巻き込みではない。bulk staging (add -A / . / -u) は path を
# 名指ししないのでここに現れず、block-add-all.sh が別途止める (= 事故経路は塞いだまま)。
extract_git_add_commands() {
  # 境界は見ない: command 文字列は改行を JSON の \n で持つため、\n の直後の git を
  # 「英数字でない文字が前置」条件で弾いてしまう (n が英数字)。ここは self 判定を
  # *広げる* 方向の grep なので、多少緩くても事故経路 (bulk staging) は塞いだまま。
  # `git -C <dir> add` のような値つきグローバルオプションも数える。
  grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]*"' "$1" 2>/dev/null \
    | grep -E 'git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+add[[:space:]]'
}

# repo 相対 path に正規化 (= 絶対 path なら repo root prefix を削除。多重 escape 回避に / 正規化)
normalize_to_rel() {
  norm_path_var "$1"
  case "$NORM_PATH" in
    "$REPO_ROOT"/*) printf '%s\n' "${NORM_PATH#$REPO_ROOT/}" ;;
    *)              printf '%s\n' "$NORM_PATH" ;;
  esac
}

# raw path 行 (stdin) → repo 相対・空行除去 (stdout)
build_set() {
  local P REL
  while IFS= read -r P; do
    [ -z "$P" ] && continue
    REL=$(normalize_to_rel "$P")
    [ -n "$REL" ] && printf '%s\n' "$REL"
  done
}

# gate 本体 — 契約は lib/standalone.sh ヘッダ参照 (global INPUT / CMD を読む)。
gate_block_cross_claude_wip() {
  local TRANSCRIPT STAGED REPO_ROOT TRANSCRIPT_DIR WINDOW_HOURS CUR_NORM SIBLINGS
  local FOREIGN_EDITED SIB SIB_NORM FE SELF_EDITED INTRUDERS S S_NORM

  cmd_invokes_git_subcommand "$CMD" commit || return 0

  # --amend も対象に含める。共有 index 構成では `git commit --amend` こそが他 session の
  # staged file を最も巻き込む経路 (実事故: 別 Terminal の 14 staged file が amend で commit に
  # 混入し origin/main へ push された)。message-only amend (index が clean) は下の
  # `[ -z "$STAGED" ] && return 0` で素通しになるので、除外しなくても over-block しない。

  # transcript_path を input から抽出 (単一権威 decoder。旧 grep 抽出は path 中の `,` `}` /
  # escape で途中切りし、transcript 不在扱いの無音 fail-open になった — 2026-07-10 監査)
  json_field_var transcript_path "$INPUT" || JSON_FIELD=""
  TRANSCRIPT="$JSON_FIELD"

  # Windows path 正規化 (= JSON-escape 済 backslash を forward slash に)
  if [ -n "$TRANSCRIPT" ]; then
    norm_path_var "$TRANSCRIPT"
    TRANSCRIPT="$NORM_PATH"
  fi

  # transcript が取れない / 存在しないなら fail-open (= 規律より AI 有用性を優先、warning のみ)
  if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
    echo "project-bootstrap: cross-claude-wip check skipped (transcript not available)" >&2
    return 0
  fi

  # git が無い / repo でない場合も素通し (repo_top_var は repo 外で空を memo する)
  repo_top_var
  REPO_ROOT="$REPO_TOP"
  [ -z "$REPO_ROOT" ] && return 0

  # staged file list (path は repo root 相対 / forward slash)
  STAGED=$(git diff --cached --name-only 2>/dev/null)
  [ -z "$STAGED" ] && return 0

# ── self-edited set (= 当 session が file 編集ツールで触った file。常に許可)
SELF_EDITED=$(extract_edited "$TRANSCRIPT" | build_set)

# ── self-staged set (= 当 session が path を名指しで `git add` した file)
# 他 session の編集が既に commit 済み / 取り消し済みで working tree に残っていなくても、
# transcript には「編集した」記録が残り続ける。その記録だけを根拠に intruder 扱いすると、
# 当 session が自分で書いて自分で stage した file の commit まで止まる (誤検知)。
# 実例: 前日の session が触った schema file を、翌日 別 session が正当に編集して commit
# しようとして止まった。編集は既に main にマージ済みで、巻き込む WIP は存在しなかった。
SELF_STAGED_CMDS=$(extract_git_add_commands "$TRANSCRIPT" || true)

# ── foreign-edited set (= 同一 working tree を共有する *他* session が編集した file)
# 同一 projects dir の sibling transcript を走査。current は除外。stale session の巻き添えを
# 避けるため、鮮度窓 (default 24h) 内に更新された sibling だけを対象にする。
TRANSCRIPT_DIR="${TRANSCRIPT%/*}"
WINDOW_HOURS="${BOOTSTRAP_WIP_WINDOW_HOURS:-24}"
CUR_NORM="$TRANSCRIPT"   # 既に norm_path_var 済み

if [ "$WINDOW_HOURS" -gt 0 ] 2>/dev/null; then
  SIBLINGS=$(find "$TRANSCRIPT_DIR" -maxdepth 1 -name '*.jsonl' -mmin "-$((WINDOW_HOURS * 60))" 2>/dev/null)
else
  SIBLINGS=$(find "$TRANSCRIPT_DIR" -maxdepth 1 -name '*.jsonl' 2>/dev/null)
fi

FOREIGN_EDITED=""
while IFS= read -r SIB; do
  [ -z "$SIB" ] && continue
  norm_path_var "$SIB"
  SIB_NORM="$NORM_PATH"
  [ "$SIB_NORM" = "$CUR_NORM" ] && continue   # 自分の transcript は sibling から除外
  FE=$(extract_edited "$SIB" | build_set)
  [ -n "$FE" ] && FOREIGN_EDITED="${FOREIGN_EDITED}${FE}
"
done <<EOF
$SIBLINGS
EOF

# 他 session の編集証拠が 1 件も無ければ block すべき file は無い (= fail-open)
[ -z "$(printf '%s' "$FOREIGN_EDITED" | tr -d '[:space:]')" ] && return 0

# ── 判定: staged file のうち self-edited に無く foreign-edited に*ある* ものだけが intruder
INTRUDERS=""
while IFS= read -r S; do
  [ -z "$S" ] && continue
  norm_path_var "$S"
  S_NORM="$NORM_PATH"
  printf '%s' "$SELF_EDITED" | grep -Fxq "$S_NORM" && continue        # 自分の編集は常に許可
  # 当 session が path を名指しで stage した file も自分のもの (= 巻き込みではない)
  if [ -n "$SELF_STAGED_CMDS" ] && printf '%s' "$SELF_STAGED_CMDS" | grep -Fq "$S_NORM"; then
    continue
  fi
  printf '%s' "$FOREIGN_EDITED" | grep -Fxq "$S_NORM" || continue     # 他 session 編集証拠が無ければ素通し
  INTRUDERS="${INTRUDERS}${S_NORM}
"
done <<EOF
$STAGED
EOF

[ -z "$(printf '%s' "$INTRUDERS" | tr -d '[:space:]')" ] && return 0

cat >&2 <<EOF
project-bootstrap: blocking commit — staged file(s) edited by ANOTHER Claude session
(同一 working tree を共有する別 session が編集した形跡があり、当 session では Edit/Write していない):

$(printf '%s' "$INTRUDERS" | sed 's/^/  - /')

並走 session / 別ターミナルの WIP を巻き込んでいる可能性が高い (= 共有 index 事故の典型)。

対処:
  - 巻き込みなら: git restore --staged <path> で除外し、自分の編集 file だけ commit
  - 本当に両 session 分を一緒に commit したいなら: /permissions で本 hook を一時 deny
  - 恒久対策: session ごとに worktree を分ける (sprint-plan skill / .bootstrap-lane)。
    共有 index をやめれば本 hook は二度と発火しない

注意: lockfile (package-lock.json 等) / migration SQL は commit すべき file。
      誤検知回避のために .gitignore で隠したり untrack しないこと (再現性が壊れる)。
      上記いずれかの正規手順で対処する。

確認 command:
  git status --porcelain
  git diff --cached --name-only
EOF
return 2
}

# 単体起動 (tests / vendoring 消費者) — dispatcher からは source されるので走らない。
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  # shellcheck source=lib/standalone.sh
  . "${BASH_SOURCE[0]%/*}/lib/standalone.sh"
  bootstrap_standalone_bash_gate gate_block_cross_claude_wip
fi
