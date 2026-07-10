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
#   3. staged file のうち、self-edited に無く foreign-edited に*ある* file だけを intruder として
#      exit 2 で block。他 session の編集証拠が無い file は素通し (= fail-open)。
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

INPUT=$(cat)

# shellcheck source=lib/parse-command.sh
. "$(dirname "$0")/lib/parse-command.sh"
if ! CMD="$(printf '%s' "$INPUT" | parse_command)"; then
  echo "project-bootstrap: could not parse the tool command from hook input — blocking to fail safe (fail-closed). If this is a false positive, disable this hook via /permissions." >&2
  exit 2
fi

[ -z "$CMD" ] && exit 0

# git commit でなければ素通し (= add / status / log 等は対象外)。検出は単一権威
# lib/git-invocation.sh (path-prefixed git / git グローバルオプション形も捕まえる — 旧 regex は
# どちらも素通りさせた。ADR 0019)。
# shellcheck source=lib/git-invocation.sh
. "$(dirname "$0")/lib/git-invocation.sh"
cmd_invokes_git_subcommand "$CMD" commit || exit 0

# --amend も対象に含める。共有 index 構成では `git commit --amend` こそが他 session の
# staged file を最も巻き込む経路 (実事故: 別 Terminal の 14 staged file が amend で commit に
# 混入し origin/main へ push された)。message-only amend (index が clean) は下の
# `[ -z "$STAGED" ] && exit 0` で素通しになるので、除外しなくても over-block しない。

# transcript_path を input から抽出 (単一権威 decoder。旧 grep 抽出は path 中の `,` `}` /
# escape で途中切りし、transcript 不在扱いの無音 fail-open になった — 2026-07-10 監査)
TRANSCRIPT=$(printf '%s' "$INPUT" | parse_json_string_field transcript_path)

# Windows path 正規化 (= JSON-escape 済 backslash を forward slash に)
if [ -n "$TRANSCRIPT" ]; then
  TRANSCRIPT=$(printf '%s' "$TRANSCRIPT" | tr '\\\\' '/' | tr -s '/')
fi

# transcript が取れない / 存在しないなら fail-open (= 規律より AI 有用性を優先、warning のみ)
if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
  echo "project-bootstrap: cross-claude-wip check skipped (transcript not available)" >&2
  exit 0
fi

# git が無い / repo でない場合も素通し
command -v git >/dev/null 2>&1 || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# staged file list (path は repo root 相対 / forward slash)
STAGED=$(git diff --cached --name-only 2>/dev/null)
[ -z "$STAGED" ] && exit 0

# repo root 取得 (= self-edited file の絶対 path を repo 相対 path に正規化するため)
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null | tr '\\\\' '/' | tr -s '/')
[ -z "$REPO_ROOT" ] && exit 0

# transcript から Edit / Write / MultiEdit / NotebookEdit の file_path / notebook_path を抽出。
# JSONL の各行から "file_path": "..." / "notebook_path": "..." を grep。
# Bash tool の command は file_path を残さないため、ここには現れない (= 旧実装の誤検知源だった
# が、新実装は self-edited に「無い」ことを罪としないので問題にならない)。
extract_edited() {
  grep -oE '"(file_path|notebook_path)"[[:space:]]*:[[:space:]]*"[^"]*"' "$1" 2>/dev/null \
    | sed 's/.*:[[:space:]]*"//; s/"$//'
}

# repo 相対 path に正規化 (= 絶対 path なら repo root prefix を削除。多重 escape 回避に / 正規化)
normalize_to_rel() {
  local P="$1"
  P=$(printf '%s' "$P" | tr '\\\\' '/' | tr -s '/')
  case "$P" in
    "$REPO_ROOT"/*) printf '%s\n' "${P#$REPO_ROOT/}" ;;
    *)              printf '%s\n' "$P" ;;
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

# ── self-edited set (= 当 session が file 編集ツールで触った file。常に許可)
SELF_EDITED=$(extract_edited "$TRANSCRIPT" | build_set)

# ── foreign-edited set (= 同一 working tree を共有する *他* session が編集した file)
# 同一 projects dir の sibling transcript を走査。current は除外。stale session の巻き添えを
# 避けるため、鮮度窓 (default 24h) 内に更新された sibling だけを対象にする。
TRANSCRIPT_DIR=$(dirname "$TRANSCRIPT")
WINDOW_HOURS="${BOOTSTRAP_WIP_WINDOW_HOURS:-24}"
CUR_NORM=$(printf '%s' "$TRANSCRIPT" | tr '\\\\' '/' | tr -s '/')

if [ "$WINDOW_HOURS" -gt 0 ] 2>/dev/null; then
  SIBLINGS=$(find "$TRANSCRIPT_DIR" -maxdepth 1 -name '*.jsonl' -mmin "-$((WINDOW_HOURS * 60))" 2>/dev/null)
else
  SIBLINGS=$(find "$TRANSCRIPT_DIR" -maxdepth 1 -name '*.jsonl' 2>/dev/null)
fi

FOREIGN_EDITED=""
while IFS= read -r SIB; do
  [ -z "$SIB" ] && continue
  SIB_NORM=$(printf '%s' "$SIB" | tr '\\\\' '/' | tr -s '/')
  [ "$SIB_NORM" = "$CUR_NORM" ] && continue   # 自分の transcript は sibling から除外
  FE=$(extract_edited "$SIB" | build_set)
  [ -n "$FE" ] && FOREIGN_EDITED="${FOREIGN_EDITED}${FE}
"
done <<EOF
$SIBLINGS
EOF

# 他 session の編集証拠が 1 件も無ければ block すべき file は無い (= fail-open)
[ -z "$(printf '%s' "$FOREIGN_EDITED" | tr -d '[:space:]')" ] && exit 0

# ── 判定: staged file のうち self-edited に無く foreign-edited に*ある* ものだけが intruder
INTRUDERS=""
while IFS= read -r S; do
  [ -z "$S" ] && continue
  S_NORM=$(printf '%s' "$S" | tr '\\\\' '/' | tr -s '/')
  printf '%s' "$SELF_EDITED" | grep -Fxq "$S_NORM" && continue        # 自分の編集は常に許可
  printf '%s' "$FOREIGN_EDITED" | grep -Fxq "$S_NORM" || continue     # 他 session 編集証拠が無ければ素通し
  INTRUDERS="${INTRUDERS}${S_NORM}
"
done <<EOF
$STAGED
EOF

[ -z "$(printf '%s' "$INTRUDERS" | tr -d '[:space:]')" ] && exit 0

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
exit 2
