# 2026-06-11-parallel-mode-gate-coverage: 統合レビュー関所が実際の並列開発 3 形態のうち 1 形態しかカバーしていなかった

user の指摘 (「並行開発は何度かあったぞ」「Workflow でサブエージェント並列のこともある」) を受けた検証で確定した **顕在化済みの穴**。gate 無音化 class の **5 例目** (advisory / 配備漏れ / stale state / unbounded state / **mode coverage**)。

Stage 2 の統合関所 (`block-unreviewed-merge.sh`, 0.15.0) は「活性 board の task branch の手元 `git merge`」だけを信号にしていた。だが実際の並列開発は board を作る正式 flow では一度も起きておらず、(a) **branch 並走 + GitHub PR merge** (creative-team-app 2026-06-03、PR #1〜#10 を 1 日で統合 — PR 画面の merge は手元 hook を物理的に通らない)、(b) **Workflow サブエージェントの隔離 worktree 並列実装** (新プロダクト P4、board 無しのため gate が眠ったまま) の 2 形態で起きていた。どの形態になるかは Claude の判断次第 (= ungoverned advisory) で、(a)(b) に転んだ日は関所が無音だった。

## 関係する file / 識別子

- `hooks/block-unreviewed-merge.sh` (旧) — 信号が board task branch のみ
- creative-team-app `git log --merges`: 2026-06-03 に `Merge pull request #1`〜`#10` (ui-polish / approval-workflow / message-attachments 等 10 branch)
- 新プロダクトの transcript: 「Workflow で並列実装 → 私が main session で統合 verify + レビュー + commit」(board 不在、起動文方式と Workflow 方式が成り行きで混在)
- 私の誤報告: この検証の直前まで「並列開発は一度もなかった」と user に報告していた (= .gate と board の不在だけを見て、merge 履歴と worktree 痕跡を見ていなかった)

## 1. ミスの一覧

### 1.1 関所の信号を「特定の方式の痕跡」(board) に結合した

- **何をした**: 0.15.0 で統合関所を設計したとき、「並列開発 = sprint flow (board.json)」と仮定し、信号を board の task branch に置いた
- **何が問題だった**: 並列開発は board を作らなくても成立する (branch + PR / Workflow worktree)。方式は強制されておらず (advisory)、関所が方式に依存すると **方式の選択がそのまま関所の on/off になる**
- **観測された結果**: 実在した並列統合 10 件 (PR 経路、関所導入前) と進行中の Workflow 並列が、いずれも関所の射程外だった

### 1.2 「並列開発はなかった」を .gate / board の不在から断定した (私の報告ミス)

- **何をした**: 適用状況チェックで .gate 全件 sequential・board 痕跡なしを見て「並列は一度も発生していない」と報告した
- **何が問題だった**: 「プラグインの正式 flow が使われていない」ことと「並列開発がない」ことを混同した。merge 履歴 (`git log --merges`) と worktree 残置という直接証拠が repo にあり、user の記憶と即座に矛盾した。SKILL の癖 7 (「不在主張の前に対象リソース自身への diagnostic を叩く」) の違反
- **観測された結果**: user の指摘で訂正。merge 履歴を見れば 10 秒で分かることだった

### 1.3 (前提の確認による好転) ADR 0001 の前提が消滅していたのに 2 週間気づいていなかった

- **何をした**: 「subagent に hook は効かない」(#21460 OPEN) を前提に設計・運用を続けていた
- **実際**: upstream は 2026-05-29 に completed で close 済み。**実測検証** (一時 repo + subagent に Write 指示 → `require-test-companion.sh` が exit 2 で blocking) で fix を確認した。前提を「一次ソースで一度検証したら不変」と扱い、再検証の trigger を持っていなかった

## 2. 真因

> **gate のカバレッジは「配備されているか」(class 2 例目) だけでなく「実際の workflow の全経路に当たっているか」も含む。** 経路 (方式) が advisory で選ばれる環境では、関所を特定方式の痕跡に結合した時点で、関所の on/off がモデルの気分に委ねられる。関所は**どの方式でも必ず通る行為** (統合の入口 = 手元 merge / PR) に、方式非依存の信号 (worktree という物理痕跡 / PR という行為そのもの) で置かなければならない。

## 3. 構造的再発防止

- [x] **手元の関所を方式非依存化**: lane branch = 活性 board の task branch ∪ linked worktree に checkout された branch (`block-unreviewed-merge.sh` 拡張、`tests/hooks/block-unreviewed-merge.test.bash` 13-17 で pin)
- [x] **PR 経路に CI 関所**: `templates/ci/bootstrap-review-gate.yml` (導入 repo では全 PR にレビュー記録を要求)。creative-team-app に配備済み
- [x] **doctrine 更新**: ADR 0004 (並列 3 形態の公認 + 統合の入口関所)、ADR 0001 を部分 supersede、SKILL.md の「subagent は read-only」節を書き換え
- [x] **upstream fix の実測検証を記録**: subagent への hook 配達を確認 (検証手順は ADR 0004)。回帰時は ADR 0001 の回避設計に戻す
- [x] **memory 昇格**: `feedback_gate_distribution_coverage` に「経路 (mode) カバレッジ」と「外部前提 (upstream issue) は閉じたら再検証」を追記

## 4. 関連 memory / docs

- `docs/decisions/0004-parallel-mode-integration-gate.md` — 本件の設計判断
- `docs/decisions/0001-subagent-hooks-not-enforced.md` — superseded された旧前提
- `docs/incidents/2026-06-02-coverage-drift-silent/` — class 2 例目 (配備カバレッジ)。本件はその「経路カバレッジ」版
- memory `feedback_gate_distribution_coverage` / `feedback_gate_signal_and_failmode`
