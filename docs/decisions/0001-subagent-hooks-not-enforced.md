# 0001 — subagent では hook が効かないので mutation を委譲せず read-only 専用にする

- **Status**: Accepted
- **Date**: 2026-05-29
- **Deciders**: Rintaro Yamaoka
- **References**: upstream [anthropics/claude-code#21460](https://github.com/anthropics/claude-code/issues/21460) (OPEN, SECURITY) / [#27533](https://github.com/anthropics/claude-code/issues/27533) (not_planned) / [#27661](https://github.com/anthropics/claude-code/issues/27661) (closed as duplicate of 上記) / 公式 docs [sub-agents](https://code.claude.com/docs/en/sub-agents)

---

## Context (背景)

本プラグインの中核は「ルール = AI の default 挙動 + **hook による deterministic 強制**」。違反は PreToolUse hook が exit 2 で blocking する。この前提が成り立つかを一次ソースで検証した結果、subagent 経路で前提が崩れることが分かった。

- **PreToolUse hook は subagent (Task / Agent ツールで起動する子エージェント) の tool 呼び出しでは発火しない**。`#21460`「[SECURITY] PreToolUse hooks not enforced on subagent tool calls, allowing security bypass」は **2026-05-29 時点で OPEN**。
- 親 session の hook / permission を subagent に**伝播させる**機能要望 `#27533` は **`not_planned` でクローズ**。直す方針はない。
- plugin が配布する subagent では、回避策とされる **frontmatter の `hooks:` フィールドも無視される**。公式 docs 明記: "For security reasons, plugin subagents do not support the `hooks`, `mcpServers`, or `permissionMode` frontmatter fields. These fields are ignored when loading agents from a plugin."
- 当時の SKILL は TDD の Red/Green/Refactor を mutating subagent (`agents/test-writer.md` / `implementer.md` / `refactorer.md`) に委譲していた。→ **プラグインが推奨する実行経路で hook (test 先行 / lane / 依存方向 / commit gate) が静かに無効化されていた** (= 中核主張の自己矛盾)。

## Decision (決定)

**強制が効く場所でしか mutate しない**。具体的には:

- **subagent は read-only 探索専用** (`Read` / `Grep` / `Glob` / 要約 / 計画下書き)。gate すべき操作が存在しないので穴にならない。
- **実体を書き換える作業 (Edit / Write / git commit) はすべて main session が行う**。TDD の Red/Green/Refactor も main session が直接担う (= 上記 3 subagent ファイルは削除)。
- **並列開発は subagent ではなく別 session の worker**。`sprint-plan` が吐く起動文を人間が別ターミナル / 別 worktree に貼って起動する。各 worker はそれ自身が main session なので hook が普通に効く。
- 採用しなかった代替案:
  - *plugin agents の frontmatter に hook 豌入* → plugin subagent では無視されるので no-op。不可。
  - *1 session 内で Claude が subagent を並列実行して実装 (案B)* → 実装が全部 ungated な subagent で走り、強制が消える。中核主張に反するので不採用。
  - *upstream の伝播修正を待つ* → `#27533` が not_planned。待っても来ない。
- backstop: hook を経由しない経路 (subagent / 人間の直 commit / 別ツール) は `scripts/arch-check.sh` + CI + git pre-commit の server 側 net が最終砦として捕まえる。

## Consequences (結果)

### 良い影響

- 「hook = 強制」の前提が、mutation が起きる全経路 (main session + 別 session worker) で**実際に成立する**ようになった。
- プラグインが推奨する実行経路に潜んでいた gate バイパス (TDD subagent) を解消。
- 入り口の摩擦はゼロのまま (sprint にするかの判断は自動 = `sprint-plan` の default 発火)。

### 悪い影響 / トレードオフ

- mutation を main session に集約するため、TDD の各フェーズで context 節約 (subagent の別 context window) の利点は失う。
- 並列開発は人間が worker を起動する手間が残る (1 session 全自動にはしない)。

### 移行後に必要な保守

- upstream `#21460` が将来 fix されたら本 ADR を見直す (= subagent でも hook が効くなら委譲を再検討できる)。Superseding ADR を起こすこと。
- 新しい skill / agent を足すときは「mutate するなら main session、subagent なら read-only」を満たすか確認する。
