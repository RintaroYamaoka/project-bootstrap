#!/usr/bin/env bash
# Hook B — PreToolUse on Bash for `git commit`
# `git commit` 直前にプロジェクト慣例のテストコマンドを実行し、fail なら exit 2 で blocking。
# failing test がある状態での commit を構造的に禁止する。
#
# テストコマンドの検出 (汎用ベストプラクティス):
#   - package.json         → npm test --silent
#   - pyproject.toml       → uv run pytest -q  (or pytest -q)
#   - go.mod               → go test ./...
#   - Cargo.toml           → cargo test --quiet
#   - Gemfile              → bundle exec rspec
#
# 検出できない場合は warning だけ出して exit 0 (= 強制しない)。
# プロジェクト固有 test command がある場合は .claude/settings.json で override する。

set -u

INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | grep -oE '"command"[^,}]*' | head -1 | sed 's/.*"command"[[:space:]]*:[[:space:]]*"//; s/"[[:space:]]*$//')

# git commit でなければ素通し
echo "$CMD" | grep -qE '(^|[[:space:]&|;]+)git[[:space:]]+commit($|[[:space:]])' || exit 0

# テストコマンドを検出
# marker を検出したら、その runner が PATH にある場合だけ TEST_CMD を立てる。
# runner 不在で TEST_CMD を立てると、存在しないコマンドの非ゼロ exit を「test fail」と
# 誤読して commit を誤 block する (= toolchain 未導入マシンで作業不能になる)。
TEST_CMD=""
if [ -f "package.json" ]; then
  if grep -q '"test"' package.json && command -v npm >/dev/null 2>&1; then
    TEST_CMD="npm test --silent"
  fi
elif [ -f "pyproject.toml" ] || [ -f "pytest.ini" ] || [ -f "setup.cfg" ]; then
  if command -v uv >/dev/null 2>&1 && [ -d ".venv" ]; then
    TEST_CMD="uv run pytest -q"
  elif command -v pytest >/dev/null 2>&1; then
    TEST_CMD="pytest -q"
  fi
elif [ -f "go.mod" ]; then
  command -v go >/dev/null 2>&1 && TEST_CMD="go test ./..."
elif [ -f "Cargo.toml" ]; then
  command -v cargo >/dev/null 2>&1 && TEST_CMD="cargo test --quiet"
elif [ -f "Gemfile" ]; then
  command -v bundle >/dev/null 2>&1 && TEST_CMD="bundle exec rspec"
fi

if [ -z "$TEST_CMD" ]; then
  echo "project-bootstrap: no test framework detected, skipping pre-commit test check" >&2
  exit 0
fi

echo "project-bootstrap: running $TEST_CMD before commit..." >&2
if ! $TEST_CMD >&2; then
  echo "project-bootstrap: tests failed — blocking commit. Fix tests before committing." >&2
  exit 2
fi
exit 0
