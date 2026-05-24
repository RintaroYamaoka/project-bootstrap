#!/usr/bin/env bash
# Hook E — PreToolUse on Bash for `git commit`
# 並列 Claude / 別ターミナル の WIP を commit に巻き込む事故を構造的に block する。
#
# 仕組み:
#   1. 現セッションの transcript (= JSONL ファイル) から Edit/Write/MultiEdit/NotebookEdit で
#      触った file_path 集合を抽出 = "self-edited set"
#   2. `git diff --cached --name-only` で staged file を取得
#   3. staged file が self-edited set に含まれていない場合、他 session の WIP を
#      巻き込んだ可能性が高いので exit 2 で blocking
#
# Claude Code は hook input JSON に session_id / transcript_path / cwd / tool_name / tool_input を渡す。
# 公式 docs: https://code.claude.com/docs/en/hooks
#
# bypass:
#   - 意図的に他 session の作業も commit したい場合は /permissions で本 hook を一時 deny
#   - transcript_path が取れない環境 (= 古い CLI / 未対応 mode) では素通し (= false negative)

set -u

INPUT=$(cat)

CMD=$(printf '%s' "$INPUT" | grep -oE '"command"[^,}]*' | head -1 | sed 's/.*"command"[[:space:]]*:[[:space:]]*"//; s/"[[:space:]]*$//')

[ -z "$CMD" ] && exit 0

# git commit でなければ素通し (= add / status / log 等は対象外)
echo "$CMD" | grep -qE '(^|[[:space:]&|;()`]+)git[[:space:]]+commit($|[[:space:]])' || exit 0

# --amend も対象に含める。共有 index 構成では `git commit --amend` こそが他 session の
# staged file を最も巻き込む経路 (実事故: 別 Terminal の 14 staged file が amend で commit に
# 混入し origin/main へ push された)。message-only amend (index が clean) は下の
# `[ -z "$STAGED" ] && exit 0` で素通しになるので、除外しなくても over-block しない。

# transcript_path を input から抽出
TRANSCRIPT=$(printf '%s' "$INPUT" | grep -oE '"transcript_path"[^,}]*' | head -1 | sed 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"//; s/"[[:space:]]*$//')

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

# transcript から Edit / Write / MultiEdit / NotebookEdit の file_path / notebook_path を抽出
# JSONL の各行から "file_path": "..." / "notebook_path": "..." を grep。
# 多重 escape を回避するため backslash を / に正規化してから比較。
EDITED_RAW=$(grep -oE '"(file_path|notebook_path)"[[:space:]]*:[[:space:]]*"[^"]*"' "$TRANSCRIPT" 2>/dev/null \
  | sed 's/.*:[[:space:]]*"//; s/"$//')

# repo 相対 path に正規化
normalize_to_rel() {
  local P="$1"
  P=$(printf '%s' "$P" | tr '\\\\' '/' | tr -s '/')
  # 絶対 path なら repo root を prefix 削除
  case "$P" in
    "$REPO_ROOT"/*) printf '%s\n' "${P#$REPO_ROOT/}" ;;
    /*) printf '%s\n' "$P" ;;
    *)  printf '%s\n' "$P" ;;
  esac
}

# self-edited set を build (改行区切り)
SELF_EDITED=""
while IFS= read -r P; do
  [ -z "$P" ] && continue
  REL=$(normalize_to_rel "$P")
  SELF_EDITED="${SELF_EDITED}${REL}
"
done <<EOF
$EDITED_RAW
EOF

# 比較: staged の各 file が SELF_EDITED に含まれているか
INTRUDERS=""
while IFS= read -r S; do
  [ -z "$S" ] && continue
  S_NORM=$(printf '%s' "$S" | tr '\\\\' '/' | tr -s '/')
  if ! printf '%s' "$SELF_EDITED" | grep -Fxq "$S_NORM"; then
    INTRUDERS="${INTRUDERS}${S_NORM}
"
  fi
done <<EOF
$STAGED
EOF

[ -z "$(printf '%s' "$INTRUDERS" | tr -d '[:space:]')" ] && exit 0

cat >&2 <<EOF
project-bootstrap: blocking commit — staged file(s) not edited by this Claude session:

$(printf '%s' "$INTRUDERS" | sed 's/^/  - /')

これらの file は当セッションで Edit/Write/MultiEdit していない。考えられる原因:
  1. 別 Claude / 別ターミナル / IDE の WIP を巻き込んでいる
  2. 手動で staged にした (= user 操作なら問題なし)
  3. test/build 副作用で生成された artifact (= lockfile / generated)

対処:
  - 巻き込みなら: git restore --staged <path> で除外、自分の編集 file だけ commit
  - 意図的なら: /permissions で本 hook を一時 deny にしてから commit
  - artifact なら: その path を .gitignore に追加するのが本筋

確認 command:
  git status --porcelain
  git diff --cached --name-only
EOF
exit 2
