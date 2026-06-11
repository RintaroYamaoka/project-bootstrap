# 0004 — 並列開発の 3 形態を公認し、統合の入口に方式非依存の関所を置く (ADR 0001 を部分的に supersede)

- **Status**: Accepted
- **Date**: 2026-06-11
- **Deciders**: Rintaro Yamaoka
- **References**: upstream [anthropics/claude-code#21460](https://github.com/anthropics/claude-code/issues/21460) (**closed: completed, 2026-05-29**) / `docs/decisions/0001-subagent-hooks-not-enforced.md` (本 ADR が部分的に supersede) / `docs/incidents/2026-06-11-parallel-mode-gate-coverage`

---

## Context (背景)

2 つの事実が同日に確定した。

**1. ADR 0001 の前提が消滅した。** 「PreToolUse hook は subagent で発火しない」(#21460) は 2026-05-29 に **completed で close** され、2026-06-11 に**実測で検証した**: 一時 repo に sprint flow を採用させ、subagent (Agent tool) に新規 source file の Write を指示したところ、plugin の `require-test-companion.sh` が exit 2 で blocking した (= subagent の tool 呼び出しにも plugin hook が届く)。「強制が効かない場所で mutate しない」という回避設計の根拠が無くなった。

**2. 実際の並列開発は、プラグインが想定した 1 形態では起きていなかった。** 関所 (`block-unreviewed-merge.sh`) は「活性 board の task branch の手元 merge」だけを見ていたが、消費先の実態は:

| 形態 | 実例 | 旧設計での関所 |
|---|---|---|
| ① 別ターミナル worker (sprint flow) | 実戦例なし | 効く (設計通り) |
| ② branch 並走 + GitHub PR merge | creative-team-app 2026-06-03、PR #1〜#10 を 1 日で統合 | **物理的に届かない** (PR merge は手元 hook を通らない) |
| ③ Workflow サブエージェント並列実装 + main session 統合 | 新プロダクトの P4 連携インフラ 4 lane | board が無いので**眠ったまま** |

どの形態になるかは Claude の気分次第 (= ungoverned) で、②③に転んだ日は Stage 2 の関所が無音になる。gate 無音化 class の 5 例目 (advisory / 配備漏れ / stale state / unbounded state / **mode coverage**)。

## Decision (決定)

**「方式」を縛るのをやめ、どの方式でも必ず通る「統合の入口」に関所を置く。**

1. **subagent の mutation を公認する** (ADR 0001 の read-only 専用ルールを撤回)。ただし並列実装は**必ず隔離 worktree** で行う (= lane の物理分離は維持。同一 tree での subagent 並走は引き続き不可)。edit 時の gate (TDD / sprint 発火 / lane / arch) は subagent にもそのまま効く (実測済み)。
2. **手元の統合関所を方式非依存にする**: `block-unreviewed-merge.sh` の信号を「活性 board の task branch」から「**並列 lane の branch** = 活性 board の task branch ∪ **linked worktree に checkout された branch**」に拡張。worktree という物理的痕跡を信号にすれば、①も③も board の有無に関わらず統合の入口で捕まる。opt-in は他 gate と同じ `docs/sprint/` の存在。
3. **PR 経路 (②) は CI に関所を置く**: `templates/ci/bootstrap-review-gate.yml`。GitHub 側では worktree の有無を判別できないため、**導入した repo では「PR を作る = 統合行為」とみなし全 PR にレビュー記録を要求**する (命名規約や語彙の proxy に逃げない)。required status check 化は「main 直接 push 運用」と両立しないため repo ごとの判断とする。
4. レビュー記録の規約は全経路で共通: `docs/sprint/reviews/<branch の / → _>.md` + `verdict: approve|reject`。

採用しなかった代替案:
- *③ (Workflow 並列実装) を gate で禁止して①に誘導* → 「実装させる workflow か」の判定が語彙解析になり構造的に穴が空く (2026-05-31 incident の再来)。ハーネスの進化 (Workflow + worktree 隔離) と恒常的に喧嘩する。subagent に hook が効く今、禁止する理由自体が無い。
- *全 branch merge にレビューを要求* (worktree 信号なし) → solo の通常 merge を全部 trip し、cry-wolf 化する (誤検知は false negative より有害)。

## Consequences (帰結)

- ADR 0001 のうち「subagent は read-only 専用 / mutation は main session のみ / 並列はターミナルのみ」は **superseded**。残る有効部分: read-only レビュー agent の設計、同一 tree での並走禁止、hook 非経由路への CI/server 側 backstop。
- 統合関所の回避路が 1 つ残る: worktree を**先に撤去してから** merge すると信号が消える。integrate skill は「merge → 撤去」の順を必須とし、逆順は手順違反として文書で禁じる (物理信号の限界。CI 側の net が PR 経路では補う)。
- subagent への hook 配達は upstream の挙動に依存する。回帰したら (= 再び発火しなくなったら) ADR 0001 の回避設計に戻す。検証手順は incident に記録済み (一時 repo + subagent Write 1 発)。
