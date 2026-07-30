# 2026-05-31-sprint-advisory-silent: sprint 発火が advisory のまま語彙穴で沈黙し、分解されずに事故になった

実アプリ開発で、feature 実装に着手しても sprint 自動分解が**一度も発火せず**、モデルが逐次 TDD に突入して 8 項目のフラットな TODO を作り「分解した気」になった (= 本物の board.json + worktree + lane の分解をスキップ)。user が後から自分で「スクラム」と打って初めて再発火した。安全網が、一番必要なタイミングで沈黙していた。

## 関係する file / 識別子

- `hooks/sprint-trigger-reminder.sh` (= 0.11.0 で追加した UserPromptSubmit リマインダ。judgment と実行はモデル任せ = advisory)
- その発火 regex `実装|機能|feature|追加して|作って|...|スクラム|並列で|複数ターミナル` (= user の語彙を信号にしていた)
- user が実際に使った語: 「全統合せよ」「いつでも移行できる状態まで完成させて」「じゃあやれ」(= 統合 / 移行 / 完成 / やれ が未登録 → 無音)

---

## 1. ミスの一覧

### 1.1 sprint 発火だけが advisory のまま残っていた

- **何をした**: 0.11.0 で「判定し忘れ」対策として reminder hook を足したが、hook は checklist を注入するだけで、判定も分解も逐次の決定もモデル任せにした
- **何が問題だった**: プラグインの中核は「advisory は忘れられるので不採用」。reminder は deterministic に「注入」はするが、肝心の「判定の実行」は advisory のまま。長い会話でモデルが流せば何も起きない
- **観測された結果**: モデルが gate を回さず逐次 TDD に突入。分解されなかった

### 1.2 発火信号が判定対象の proxy (語彙) だった

- **何をした**: 「これは feature 実装か」を、user prompt の語彙 regex で代理した
- **何が問題だった**: 判定したいのは「これから feature 面を作るか」なのに、信号が「user が特定の単語を使ったか」になっていた。自然言語の言い回しは無限なので regex は構造的に穴を持つ
- **観測された結果**: 着手を指示する語 (統合/移行/完成/やれ) が未登録で、最も必要な局面で無音だった

### 1.3 前回の対処方針が「語彙を足す」に流れかけた

- **何をした**: 初動の診断は「regex に統合/移行/完成/やれ が無いのが副因」と結論しかけた
- **何が問題だった**: それは穴を移動させるだけ。proxy 信号のまま次の言い回しで再発する。memory `feedback_gate_signal_and_failmode`「gate は判定対象そのものを信号にする」に反する
- **観測された結果**: (実装前に再設計へ切り替えたため未発生)

## 2. 真因

> sprint 発火機構だけがプラグイン自身の中核理念に違反していた。理念は「hook で deterministic 強制 / advisory は不採用」なのに、sprint 発火は reminder を注入する**だけ**で、判定の実行はモデル任せ = advisory。さらにその信号は判定対象 (feature 面を作る行為) の proxy である「prompt の語彙」で、言い回しに依存して穴が空いた。**反 advisory を掲げる系の中に残った唯一の advisory が、まさに advisory の失敗モードで沈黙した。**

## 3. 構造的再発防止

- [x] **hook**: `block-unplanned-feature-build.sh` (PreToolUse) を新設。判定対象そのもの (= 新規 source file を作る行為) を信号にし、`docs/sprint/.gate` / `board.json` に判定の記録が無ければ `exit 2` で fail-closed に blocking。TDD/lane/arch と同型 (hook は分解を代行しないが「判定の存在」を強制する)。語彙非依存なので言い回しの穴が原理的に消える
- [x] **fail-open 既定**: 既存 file 編集 / test / config / doc / 非 source / `docs/sprint/` 未採用は素通し (= 根拠不在は通す)。bug fix / refactor は trip しない
- [x] **mid-session 再発火**: `.gate` に記録した scope 外の新規 source を作ると再 block (= 新しい disjoint 面で再判定)。今回の「会話途中で新 feature が増えた」経路を捕まえる
- [x] **reminder の降格**: `sprint-trigger-reminder.sh` は早期ヒントとして存置。強制本体は gate なので語彙 regex の取りこぼしは致命的でない
- [x] **ADR**: 設計転換を `docs/decisions/0002-sprint-gate-fail-closed.md` に記録 (採用しなかった「語彙拡張」「soft 維持」「commit-time 検証」も明記)
- [x] **test**: `tests/hooks/block-unplanned-feature-build.test.bash` で opt-in / 新規 source block / .gate scope 一致・scope 外再発火 / 既存編集・test・config の fail-open / 非 git / artifact 自身の Write を pin
- [x] **memory 昇格**: `feedback_gate_signal_and_failmode` に「反 advisory 系の中の advisory 残置が穴。前進行為に precondition を課し、判定対象そのものを信号にする」を追記

## 4. 関連 memory / docs

- `docs/decisions/0002-sprint-gate-fail-closed.md` — 本修正の ADR
- `docs/decisions/0001-subagent-hooks-not-enforced.md` — 「hook は意味的な仕事を代行できないが前進行為は強制できる」doctrine の先例 (subagent 版)
- `docs/incidents/2026-05-29-cross-wip-bash-false-positive/README.md` — 同 memory「gate の信号設計」を確立した先行事故
- memory `feedback_gate_signal_and_failmode` — 昇格した教訓
- CHANGELOG `[Unreleased]` — 本修正
