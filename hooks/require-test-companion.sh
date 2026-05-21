#!/usr/bin/env bash
# Hook A — PreToolUse on Edit|Write|MultiEdit
# 実装ファイルを編集しようとした瞬間、対応 test ファイルが無ければ exit 2 で blocking。
# 「テスト書かずに実装」を default で構造的に不可能にする (= Red phase 強制)。
#
# 検出する慣例 (汎用ベストプラクティス):
#   - foo.ts        → foo.test.ts / foo.spec.ts / foo_test.ts / __tests__/foo.test.ts / tests/foo.test.ts
#   - foo.py        → test_foo.py (同 dir or tests/)
#   - foo.go        → foo_test.go (同 dir)
#   - foo.rs        → tests/foo.rs
#
# test ファイル自身 / markdown / config / settings の編集は素通し。
#
# 失敗時は exit 2 + stderr に理由を出力 (Claude Code が AI に feedback)。

set -u

INPUT=$(cat)
FILE=$(printf '%s' "$INPUT" | grep -oE '"file_path"[^,}]*' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"//; s/"[[:space:]]*$//')

# file_path が無ければ path フィールドを試す
if [ -z "$FILE" ]; then
  FILE=$(printf '%s' "$INPUT" | grep -oE '"path"[^,}]*' | head -1 | sed 's/.*"path"[[:space:]]*:[[:space:]]*"//; s/"[[:space:]]*$//')
fi

[ -z "$FILE" ] && exit 0

# Windows path 正規化 (= `\` を `/` に置換、case パターン match のため)。
# Claude Code は Windows 環境で JSON escape 済の backslash 区切り絶対 path を渡してくるが
# (= hook 内では literal 2 文字 `\\` が保持される)、case `*/scripts/_*` 等のパターンは
# forward slash 想定なので、正規化しないと素通し判定が効かない。
# 注意: `sed -e 's|\\|/|g'` は Git Bash の GNU sed で「unterminated `s' command」を吐いて
# FILE_NORM を空にし全 skip 経路を殺す。`tr` で character-class 単位の確実な置換 +
# `tr -s '/'` で連続 `/` を 1 つに縮約 (= 重複 `//` 対策) の組み合わせを使う。
FILE_NORM=$(printf '%s' "$FILE" | tr '\\\\' '/' | tr -s '/')

# test ファイル自身 / config / docs は素通し
case "$FILE_NORM" in
  *.test.*|*.spec.*|*_test.*|test_*.py|*/tests/*|*/test/*|*/__tests__/*|*/_test/*) exit 0 ;;
  *.md|*.json|*.yaml|*.yml|*.toml|*.ini|*.cfg|*.lock|*.txt|*.env|*.sh|*.bash|*.zsh|*.fish|*.gitignore|*.dockerignore) exit 0 ;;
  *Dockerfile*|*Makefile*|*.sql) exit 0 ;;
  # scripts/_* は ephemeral debug namespace (= 一回限りの調査 / recovery script)、test 不要で素通し。
  # 慣行: `scripts/_foo.mjs` のような prefix `_` で「使い捨て」を示す。
  */scripts/_*|scripts/_*) exit 0 ;;
esac

# 実装ファイル拡張子か
EXT="${FILE##*.}"
case "$EXT" in
  ts|tsx|js|jsx|mjs|cjs|py|go|rs|rb|php|java|cs|cpp|cc|c|h|hpp|swift|kt|scala|ex|exs|clj|hs|ml) ;;
  *) exit 0 ;;
esac

BASE="${FILE%.*}"
NAME=$(basename "$BASE")
DIR=$(dirname "$FILE")

# 慣例 test ファイル候補
CANDIDATES=(
  "${BASE}.test.${EXT}"
  "${BASE}.spec.${EXT}"
  "${BASE}_test.${EXT}"
  "${DIR}/__tests__/${NAME}.test.${EXT}"
  "${DIR}/__tests__/${NAME}.spec.${EXT}"
  "${DIR}/_test/${NAME}.${EXT}"
  "tests/${NAME}.test.${EXT}"
  "tests/${NAME}.spec.${EXT}"
  "tests/${NAME}_test.${EXT}"
  "test/${NAME}.test.${EXT}"
  "test/${NAME}_test.${EXT}"
)

case "$EXT" in
  py)
    CANDIDATES+=(
      "${DIR}/test_${NAME}.py"
      "tests/test_${NAME}.py"
      "test/test_${NAME}.py"
    )
    ;;
  go)
    CANDIDATES+=("${BASE}_test.go")
    ;;
  rs)
    CANDIDATES+=("tests/${NAME}.rs" "tests/${NAME}_test.rs")
    ;;
  rb)
    CANDIDATES+=(
      "spec/${NAME}_spec.rb"
      "spec/${DIR#*/}/${NAME}_spec.rb"
    )
    ;;
esac

# tests/ 配下の深い階層 (tests/unit/infrastructure/foo.test.ts 等) も拾う。
# 既存 CANDIDATES は tests/${NAME}.test.${EXT} 直下のみだったため、リポジトリで
# tests/unit/<layer>/ の構造を採用すると red test 済みでも hook が誤検知していた。
if [ -d tests ] || [ -d test ]; then
  while IFS= read -r found; do
    [ -n "$found" ] && CANDIDATES+=("$found")
  done < <(find tests test 2>/dev/null -type f \( \
    -name "${NAME}.test.${EXT}" -o \
    -name "${NAME}.spec.${EXT}" -o \
    -name "${NAME}_test.${EXT}" \
  \))
fi

for C in "${CANDIDATES[@]}"; do
  if [ -f "$C" ]; then
    exit 0
  fi
done

cat >&2 <<EOF
project-bootstrap: blocking edit on "$FILE" — no companion test file found.

Write a failing test first (Red phase). The hook searched these locations:
$(printf '  - %s\n' "${CANDIDATES[@]}")

If this is genuinely a non-tested file (e.g. type-only declarations, generated code), bypass this hook with /permissions or add the file to an exception list.
EOF
exit 2
