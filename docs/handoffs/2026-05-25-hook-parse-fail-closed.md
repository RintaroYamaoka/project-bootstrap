# 2026-05-25 hook 解析 fail-closed 化 + self-CI + cross-platform

## 1 行で言うと

7 hook の JSON コマンド解析を `hooks/lib/parse-command.sh` に集約し fail-open → fail-closed 化、self-CI 追加、cross-platform 用 `.gitattributes` 追加。全 13 suite green (0 failed)。**未 commit (staged + untracked)**。

## 2. 残課題

| 識別子 | 状況 | 対応案 |
|---|---|---|
| commit | 全変更が未 commit。test gate は green なので通せる | Conventional Commits で `fix:` + `feat:`(CI) を 1 commit に。`git add` は path 指定で (block-add-all が効く) |
| `\uXXXX` デコード | parse-command.sh は未対応 (shell コマンドで稀のため意図的に保留)。コメント済 | 必要になったら parse_command の `case` に `u)` 分岐追加 |
| バージョン | CHANGELOG は Unreleased に積んだのみ。番号未確定 | bugfix + 追加機能なので 0.9.1 か 0.10.0 を release 時に判断 |

## 3. バックグラウンドプロセス

なし。

## 4. 触ったファイル

**永続化したい (commit 対象):**
- `hooks/lib/parse-command.sh` (新規) — 共通 parser
- `hooks/block-{add-all,arch-violations,commit-if-lint-fails,commit-if-tests-fail,cross-claude-wip,dangerous-git-ops,push-to-protected}.sh` — 解析行を共通関数 + fail-closed に置換 (7 ファイル)
- `tests/hooks/parse-command.test.bash` (新規) — parser の unit test
- `tests/hooks/block-{add-all,dangerous-git-ops,push-to-protected}.test.bash` — コンマ/エスケープ regression + fail-closed ケース追加
- `.github/workflows/test.yml` (新規) — self-CI (ubuntu で run.sh)
- `.gitattributes` (新規) — `* eol=lf` で WSL/Windows/macOS 共通化
- `CHANGELOG.md` / `README.md` — 記述更新
- `docs/incidents/2026-05-25-hook-command-parse-fail-open/README.md` (新規)

**ephemeral:** なし (テスト fixture は mktemp で自動)

## 5. 重要な memory / docs references (読む順)

1. `docs/incidents/2026-05-25-hook-command-parse-fail-open/README.md` — 何を/なぜ直したか
2. memory `feedback_fail_closed_security_gates.md` — 昇格した教訓
3. `hooks/lib/parse-command.sh` のヘッダコメント — parser 契約

## 6. 検証手順

```bash
# 全 suite (期待: SUITES: 13 run, 0 failed)
bash tests/hooks/run.sh

# fail-open バグの repro が今は block されること (期待: exit 2)
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"fix, bug\" && git add -A"}}' | bash hooks/block-add-all.sh; echo "exit=$?"
```

## 7. 次セッションへの起動文

```
docs/handoffs/2026-05-25-hook-parse-fail-closed.md を読んで状況把握してから、
残課題の commit から進めて (test gate green、変更は path 指定で add)。
```
