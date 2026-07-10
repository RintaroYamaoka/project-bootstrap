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
# shellcheck source=lib/parse-command.sh
. "$(dirname "$0")/lib/parse-command.sh"
if ! CMD="$(printf '%s' "$INPUT" | parse_command)"; then
  echo "project-bootstrap: could not parse the tool command from hook input — blocking to fail safe (fail-closed). If this is a false positive, disable this hook via /permissions." >&2
  exit 2
fi

# git commit でなければ素通し。検出は単一権威 lib/git-invocation.sh (path-prefixed git /
# git グローバルオプション形も捕まえる — 旧 regex はどちらも素通りさせた。ADR 0019)。
# shellcheck source=lib/git-invocation.sh
. "$(dirname "$0")/lib/git-invocation.sh"
cmd_invokes_git_subcommand "$CMD" commit || exit 0

# テストコマンドを検出 (= 共有エンジン。merge 関所 block-unreviewed-merge.sh と同一権威で
# 「テストとは何か」が drift しないようにする — ADR 0005 guard 1)。marker を検出しても
# runner が PATH に無ければ立てない (= 存在しないコマンドの非ゼロ exit を test fail と誤読
# して commit を誤 block するのを防ぐ。toolchain 未導入マシンで作業不能になる)。
# shellcheck source=lib/detect-test-suite.sh
. "$(dirname "$0")/lib/detect-test-suite.sh"
if ! TEST_CMD="$(detect_test_command)"; then
  echo "project-bootstrap: no test framework detected, skipping pre-commit test check" >&2
  exit 0
fi

echo "project-bootstrap: running $TEST_CMD before commit..." >&2
if ! $TEST_CMD >&2; then
  echo "project-bootstrap: tests failed — blocking commit. Fix tests before committing." >&2
  exit 2
fi
exit 0
