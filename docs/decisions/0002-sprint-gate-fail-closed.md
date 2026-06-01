# 0002 — sprint 発火を advisory リマインダから fail-closed gate に作り替える

- **Status**: Accepted
- **Date**: 2026-05-31
- **Deciders**: Rintaro Yamaoka
- **References**: `docs/incidents/2026-05-31-sprint-advisory-silent/README.md` / [0001](./0001-subagent-hooks-not-enforced.md) / memory `feedback_gate_signal_and_failmode`

---

## Context (背景)

本プラグインの中核は「ルール = AI の default 挙動 + **hook による deterministic 強制**。advisory (slash / 明示呼び出し / リマインダ) は忘れられるので不採用」(README / SKILL「ルールとは」)。

だが sprint 自動分解の発火だけは、この方針の例外として **advisory のまま**残っていた:

- `hooks/sprint-trigger-reminder.sh` (UserPromptSubmit, 0.11.0 で追加) は 3 条件 checklist を context に注入する**だけ**。実際に判定して分解するのも、逐次でいくと決めるのも**モデル任せ**。hook 自身は sprint を起動できず、止めもしない。
- その発火信号は **user prompt の語彙** (`実装|機能|追加して|...` の regex)。自然言語の言い回しは無限なので構造的に穴があり、「全統合せよ」「いつでも移行できる状態まで完成させて」「やれ」等は 1 つもヒットしなかった。
- 結果、実アプリ開発で sprint 分解が一度も発火せず、モデルが逐次 TDD に突入して事故になった (incident 2026-05-31)。これはプラグインが他所で否定している「advisory は忘れられる」失敗モードそのものが、唯一の例外箇所で的中した。

「sprint を hook で**起動**することはできない」(worktree 起動=人間 / disjoint 判定=モデル) は 0001 で確立した既約な制約で、これは正しい。だが「起動できない」と「判定を強制できない」は別問題だった。

## Decision (決定)

**sprint 発火判定を、advisory リマインダから fail-closed gate に作り替える** (`hooks/block-unplanned-feature-build.sh`, PreToolUse on Edit|Write|MultiEdit)。

TDD/lane/arch hook と同型にする — hook は意味的な仕事 (良い test を書く / 層を設計する / 正しく分解する) を代行できないが、**前進行為の precondition は強制できる**:

- **信号 = 判定対象そのもの**。「feature 面を作る」という判定を、その proxy (prompt の語彙) ではなく **新規 source file を作る行為そのもの**で捕まえる。語彙の言い回しに依存しないので穴が原理的に塞がる。
- **fail-closed**: `docs/sprint/` を採用した project で、新規 source file を作ろうとした瞬間に、判定の記録 (`docs/sprint/.gate`) も進行中 sprint (`board.json`) も無ければ `exit 2`。
- **記録 artifact** = `docs/sprint/.gate` (gitignore, ephemeral)。逐次でいくと決めたら scope glob + 理由を 1 行記録して続行。記録 scope 外の新規 source を作ると再 block (= mid-session の新しい disjoint 面で再判定)。
- hook は **sprint を起動しない**。「判定を済ませた precondition」だけを強制する (= 0001 の制約を侵さない)。
- **fail-open (根拠不在)**: file_path 不在 / 非 git / `docs/sprint/` 未採用 / 既存 file 編集 / test・config・doc / 非 source 拡張子。bug fix / refactor は trip しない (memory `feedback_gate_signal_and_failmode` の「根拠不在=fail-open」に準拠)。
- 旧 `sprint-trigger-reminder.sh` は **早期ヒントに降格して存置**。強制本体は gate なので語彙 regex の取りこぼしはもう致命的でない。

### 採用しなかった代替案

- *語彙 regex を広げる (統合/移行/完成/やれ を足す)* → proxy 信号のまま。次は別の言い回しで同じ穴が開く。穴を移動させるだけで根治しない。
- *soft (block せず context 注入のみ) に留める* → advisory のまま = 「忘れられる」失敗モードを温存。中核方針に反する。
- *commit 時に検証する* → 逐次で組み終わった後に並列化はできない (sprint は build 前の分解)。commit-time net は TDD/arch には効くが sprint には遅すぎる。

## Consequences (結果)

### 良い影響

- 「hook = 強制」の前提が、sprint 発火にも**実際に成立**するようになった。プラグイン唯一の advisory 例外を解消。
- 信号が行為になったので、user がどんな言葉で着手を指示しても (= 語彙非依存に) 必ず判定を通る。今回すり抜けた経路が塞がった。

### 悪い影響 / トレードオフ

- 強制できるのは「判定の存在」だけ。**正しく分解させる・worker を起動させることは依然強制不能** (= 0001 の既約な残余。TDD hook が「良い test」を強制できず存在だけ強制するのと同じ)。`.gate` に雑な 1 行を書けば通る点も TDD と同型のトレードオフ。
- over-fire: 複数 file を作る正当な逐次作業 (例: 新規モジュール群) は trip する。コストは `.gate` 1 行。
- opt-in なので `docs/sprint/` 未採用 project では発火しない (= sprint flow を採らない project に friction を課さない設計判断)。

### 移行後に必要な保守

- 新 source 拡張子 / test 慣行が増えたら hook の allowlist / skip case を更新する (require-test-companion と同じ保守点)。
- upstream `#21460` が fix され subagent でも hook が効くようになっても、本 gate は main session の Write を見ているので影響を受けない (0001 とは独立)。
