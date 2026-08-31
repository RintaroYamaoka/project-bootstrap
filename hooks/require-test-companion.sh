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

# field 抽出は単一権威 lib/parse-command.sh の decoder に委ねる。旧 grep 抽出は path 中の
# `,` `}` / escape で途中切りし、この gate を無音 fail-open にした (2026-07-10 監査)。
# shellcheck source=lib/parse-command.sh
. "${BASH_SOURCE[0]%/*}/lib/parse-command.sh"

# gate 本体 — 契約は lib/standalone.sh ヘッダ参照 (global FILE を読む / return 0=pass, 2=block)。
gate_require_test_companion() {
  local FILE_NORM EXT BASE NAME DIR ROOT CANDIDATES found C

# Windows path 正規化 (= `\` を `/` に置換、case パターン match のため)。
# Claude Code は Windows 環境で JSON escape 済の backslash 区切り絶対 path を渡してくるが
# (= hook 内では literal 2 文字 `\\` が保持される)、case `*/scripts/_*` 等のパターンは
# forward slash 想定なので、正規化しないと素通し判定が効かない。正規化は fork ゼロの
# 単一権威 norm_path_var (lib/parse-command.sh) — 旧実装の `tr '\\' '/' | tr -s '/'` と
# 同じ規則 (backslash → slash、連続 slash の縮約)。sed が使えない理由は同 lib 参照。
norm_path_var "$FILE"
FILE_NORM="$NORM_PATH"

# test ファイル自身 / config / docs は素通し
case "$FILE_NORM" in
  *.test.*|*.spec.*|*_test.*|test_*.py|*/tests/*|*/test/*|*/__tests__/*|*/_test/*) return 0 ;;
  *.md|*.json|*.yaml|*.yml|*.toml|*.ini|*.cfg|*.lock|*.txt|*.env|*.sh|*.bash|*.zsh|*.fish|*.gitignore|*.dockerignore) return 0 ;;
  *Dockerfile*|*Makefile*|*.sql) return 0 ;;
  # scripts/_* は ephemeral debug namespace (= 一回限りの調査 / recovery script)、test 不要で素通し。
  # 慣行: `scripts/_foo.mjs` のような prefix `_` で「使い捨て」を示す。
  */scripts/_*|scripts/_*) return 0 ;;
esac

# 実装ファイル拡張子か
EXT="${FILE##*.}"
case "$EXT" in
  ts|tsx|js|jsx|mjs|cjs|py|go|rs|rb|php|java|cs|cpp|cc|c|h|hpp|swift|kt|scala|ex|exs|clj|hs|ml) ;;
  *) return 0 ;;
esac

BASE="${FILE%.*}"
NAME="${BASE##*/}"
DIR="${FILE%/*}"
[ "$DIR" = "$FILE" ] && DIR="."

# file が属する project root（marker を上方向に探索）。見つからなければ cwd（従来挙動）。
# session cwd と別 tree（worktree / 別 repo）のファイル編集でも、その tree の tests/ を
# 見るため（cwd 基準だと companion 実在でも誤 block・cwd 側の他人の test で誤 pass する
# — 実測 2026-07-24）。
ROOT="$DIR"
while [ -n "$ROOT" ] && [ "$ROOT" != "/" ] && [ "$ROOT" != "." ]; do
  if [ -e "$ROOT/package.json" ] || [ -e "$ROOT/pyproject.toml" ] || [ -e "$ROOT/go.mod" ] || \
     [ -e "$ROOT/Cargo.toml" ] || [ -e "$ROOT/Gemfile" ] || [ -e "$ROOT/.git" ]; then
    break
  fi
  case "$ROOT" in
    */*) ROOT="${ROOT%/*}"; [ -z "$ROOT" ] && ROOT="/" ;;
    *)   ROOT="." ;;
  esac
done
if [ -z "$ROOT" ] || [ "$ROOT" = "/" ] || [ "$ROOT" = "." ]; then
  ROOT="$PWD"
fi

# 慣例 test ファイル候補
CANDIDATES=(
  "${BASE}.test.${EXT}"
  "${BASE}.spec.${EXT}"
  "${BASE}_test.${EXT}"
  "${DIR}/__tests__/${NAME}.test.${EXT}"
  "${DIR}/__tests__/${NAME}.spec.${EXT}"
  "${DIR}/_test/${NAME}.${EXT}"
  "${ROOT}/tests/${NAME}.test.${EXT}"
  "${ROOT}/tests/${NAME}.spec.${EXT}"
  "${ROOT}/tests/${NAME}_test.${EXT}"
  "${ROOT}/test/${NAME}.test.${EXT}"
  "${ROOT}/test/${NAME}_test.${EXT}"
)

case "$EXT" in
  py)
    CANDIDATES+=(
      "${DIR}/test_${NAME}.py"
      "${ROOT}/tests/test_${NAME}.py"
      "${ROOT}/test/test_${NAME}.py"
    )
    ;;
  go)
    CANDIDATES+=("${BASE}_test.go")
    ;;
  rs)
    CANDIDATES+=("${ROOT}/tests/${NAME}.rs" "${ROOT}/tests/${NAME}_test.rs")
    ;;
  rb)
    CANDIDATES+=(
      "${ROOT}/spec/${NAME}_spec.rb"
      "${ROOT}/spec/${DIR#*/}/${NAME}_spec.rb"
    )
    ;;
esac

# tests/ 配下の深い階層 (tests/unit/infrastructure/foo.test.ts 等) も拾う。
# 既存 CANDIDATES は tests/${NAME}.test.${EXT} 直下のみだったため、リポジトリで
# tests/unit/<layer>/ の構造を採用すると red test 済みでも hook が誤検知していた。
if [ -d "$ROOT/tests" ] || [ -d "$ROOT/test" ]; then
  while IFS= read -r found; do
    [ -n "$found" ] && CANDIDATES+=("$found")
  done < <(find "$ROOT/tests" "$ROOT/test" -type f \( \
    -name "${NAME}.test.${EXT}" -o \
    -name "${NAME}.spec.${EXT}" -o \
    -name "${NAME}_test.${EXT}" \
  \) 2>/dev/null)
fi

for C in "${CANDIDATES[@]}"; do
  if [ -f "$C" ]; then
    return 0
  fi
done

cat >&2 <<EOF
project-bootstrap: blocking edit on "$FILE" — no companion test file found.

Write a failing test first (Red phase). The hook searched these locations:
$(printf '  - %s\n' "${CANDIDATES[@]}")

If this is genuinely a non-tested file (e.g. type-only declarations, generated code), bypass this hook with /permissions or add the file to an exception list.
EOF
return 2
}

# 単体起動 (tests / vendoring 消費者) — dispatcher からは source されるので走らない。
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  # shellcheck source=lib/standalone.sh
  . "${BASH_SOURCE[0]%/*}/lib/standalone.sh"
  bootstrap_standalone_edit_gate gate_require_test_companion
fi
