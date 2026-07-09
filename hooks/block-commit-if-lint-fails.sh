#!/usr/bin/env bash
# Hook J — PreToolUse on Bash for `git commit`
# `git commit` 直前に project の lint command を実行し、fail なら exit 2 で blocking。
# 「綺麗なコード」のうち **deterministic に検査できる層 (= project が自分で決めた linter 規則:
# 命名規約 / format / 未使用 / 複雑度しきい値)** だけを強制する。命名の質・設計のセンスといった
# 判断 (taste) は対象外 (= linter が見ない部分は人間レビュー / code-review skill の領分)。
#
# プラグインが綺麗さを判断するのではなく、project の linter に委ねる (= depcruise を arch で
# 使うのと同思想)。linter が解決できなければ warn して exit 0 (= 強制しない)。
#
# runner 不在ガード必須: linter が PATH に無いまま command を立てると、存在しないコマンドの
# 非ゼロ exit を「lint fail」と誤読して commit を誤 block する (= 過去 test hook で踏んだ穴)。

set -u

INPUT=$(cat)
# shellcheck source=lib/parse-command.sh
. "$(dirname "$0")/lib/parse-command.sh"
if ! CMD="$(printf '%s' "$INPUT" | parse_command)"; then
  echo "project-bootstrap: could not parse the tool command from hook input — blocking to fail safe (fail-closed). If this is a false positive, disable this hook via /permissions." >&2
  exit 2
fi

# git commit でなければ素通し
echo "$CMD" | grep -qE '(^|[[:space:]&|;()`]+)git[[:space:]]+commit($|[[:space:]])' || exit 0

# opt-in: lint marker が無ければ発火しない (= arch/lane/protected と同じ project-local
# 宣言で opt-in)。lint は project ごとに linter 設定が違い、未設定 (= `next lint` が ESLint
# 未設定で対話プロンプトに落ちる等) のリポを always-on で巻き込むと commit を壊すため。
# marker は `.bootstrap/lint` (新) / `.bootstrap-lint` (旧) どちらでも可 (resolve-marker.sh)。
# shellcheck source=lib/resolve-marker.sh
. "$(dirname "$0")/lib/resolve-marker.sh"
TOP=$(git rev-parse --show-toplevel 2>/dev/null)
[ -f "$(resolve_marker "${TOP:-.}" lint)" ] || exit 0

# lint command を検出 (runner が PATH にある場合のみ立てる)。
# SCOPED_BASE が非空なら「この commit が運ぶ file だけ」を lint できる (= 判定対象そのものを信号に
# する。ADR 0018)。空なら従来どおりツリー全体 (go/cargo は package 単位で file 引数を取れない)。
# shellcheck source=lib/lint-scope.sh
. "$(dirname "$0")/lib/lint-scope.sh"

LINT_CMD=""
SCOPED_BASE=""
SCOPED_TOOL=""
if [ -f "package.json" ]; then
  if grep -q '"lint"' package.json && command -v npm >/dev/null 2>&1; then
    LINT_CMD="npm run lint --silent"
    LINT_SCRIPT=$(grep -oE '"lint"[[:space:]]*:[[:space:]]*"[^"]*"' package.json | head -1 | sed 's/.*:[[:space:]]*"//; s/"$//')
    SCOPED_TOOL=$(lint_script_tool "$LINT_SCRIPT")
    SCOPED_BASE=$(lint_scoped_base "$LINT_SCRIPT")
  fi
elif [ -f "pyproject.toml" ] || [ -f "setup.cfg" ] || [ -f ".ruff.toml" ] || [ -f ".flake8" ]; then
  if command -v ruff >/dev/null 2>&1; then
    LINT_CMD="ruff check ."; SCOPED_TOOL=ruff; SCOPED_BASE="ruff check"
  elif command -v flake8 >/dev/null 2>&1; then
    LINT_CMD="flake8"; SCOPED_TOOL=flake8; SCOPED_BASE="flake8"
  fi
elif [ -f "go.mod" ]; then
  command -v golangci-lint >/dev/null 2>&1 && LINT_CMD="golangci-lint run"
elif [ -f "Cargo.toml" ]; then
  command -v cargo >/dev/null 2>&1 && LINT_CMD="cargo clippy --quiet -- -D warnings"
elif [ -f "Gemfile" ]; then
  if command -v rubocop >/dev/null 2>&1; then
    LINT_CMD="rubocop"; SCOPED_TOOL=rubocop; SCOPED_BASE="rubocop"
  fi
fi

if [ -z "$LINT_CMD" ]; then
  echo "project-bootstrap: no linter detected, skipping pre-commit lint check" >&2
  exit 0
fi

# scope できるなら commit が運ぶ file に絞る。
if [ -n "$SCOPED_BASE" ]; then
  # shellcheck source=lib/commit-files.sh
  . "$(dirname "$0")/lib/commit-files.sh"
  FILES=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ -f "$f" ] || continue                    # 削除された file は lint しない
    lint_ext_ok "$SCOPED_TOOL" "$f" || continue
    FILES="$FILES $f"
  done <<EOF
$(commit_files_from_cmd "$CMD")
EOF

  # commit がこの linter の扱う file を 1 つも運ばないなら、判定対象が無い → 素通し。
  if [ -z "${FILES# }" ]; then
    echo "project-bootstrap: commit touches no $SCOPED_TOOL-lintable file, skipping lint" >&2
    exit 0
  fi

  echo "project-bootstrap: running $SCOPED_BASE on this commit's files before commit..." >&2
  # shellcheck disable=SC2086
  if ! $SCOPED_BASE $FILES >&2; then
    cat >&2 <<EOF
project-bootstrap: lint failed on this commit's own files — blocking commit
(= 命名規約 / format / 未使用 / 複雑度)。意図的に通すなら /permissions で本 hook を一時 deny。

対象 (この commit が運ぶ file のみ):$FILES
EOF
    exit 2
  fi
  exit 0
fi

# fallback: file 引数を取れない linter (go/cargo 等) はツリー全体。lane worker が自分の所有しない
# debt で止まりうるが、その場合 **lane を出て直しに行ってはならない** (= 越境編集は別 gate が
# block する)。lead に上げるか /permissions で一時 deny する。
echo "project-bootstrap: running $LINT_CMD before commit..." >&2
if ! $LINT_CMD >&2; then
  cat >&2 <<EOF
project-bootstrap: lint failed — blocking commit (= 命名規約 / format / 未使用 / 複雑度)。
意図的に通すなら /permissions で本 hook を一時 deny。

この linter は file 引数を取れないためツリー全体を検査した。失敗が **自分の lane の外** の file に
由来するなら、それを直しに lane を出てはいけない (= 越境編集)。lead に上げること。
EOF
  exit 2
fi
exit 0
