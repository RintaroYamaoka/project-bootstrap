# 2026-06-07-stale-board-gate-bypass: 完了済み board.json が sprint gate を無音バイパスさせていた

`.bootstrap-wip` 導入 (= wip_limit ハードコード修正) の read-only 探索中に発見した **latent な穴** (= 事故が顕在化する前に見つかった。被害ゼロだが、gate 無音化 class の 3 例目なので起票する)。

`hooks/block-unplanned-feature-build.sh` は「進行中 sprint なら lane hook が scope を握る」として `[ -s docs/sprint/board.json ] && exit 0` で素通ししていた。だが board.json は per-sprint の ephemeral state で、**sprint が終わっても archive されなければ残る**。この repo 自身が 2026-05-24 の全 task `done` の board を残しており、その日以降この repo では sprint 発火 gate が**一度も発火し得ない状態**だった。0.12.0 で advisory を fail-closed gate に作り替え、0.13.0 で配備漏れを doctor で可視化した — その同じ gate が、自陣の repo で stale state により無音で死んでいた。

## 関係する file / 識別子

- `hooks/block-unplanned-feature-build.sh:77` — `[ -s "$TOP/docs/sprint/board.json" ] && exit 0` (= 「存在」を「活性」と読む信号設計)
- `docs/sprint/board.json` — `2026-05-24-hook-test-backfill`、全 task `done`、archive されず残置
- `skills/integrate/SKILL.md` Step 4 — 「board.json は**次 sprint まで残すか** archive する」(= 残置を公認していた)

---

## 1. ミスの一覧

### 1.1 gate の信号に「board の存在」を使った (活性ではなく)

- **何をした**: 0.12.0 で gate を実装したとき、「進行中 sprint」の判定を `board.json が非空か` に置いた
- **何が問題だった**: board.json の lifecycle には「全 task done で sprint 終了したが archive 前」という終端状態があり、そこでは「存在」と「活性」が乖離する。存在を信号にした gate は、state の lifecycle 終端で**素通し側に**死ぬ (= fail-open 方向の無音)
- **観測された結果**: この repo で 2026-05-24 以降、新規 source file の作成が sprint 判定なしで素通しになっていた (実害は未発生 — その間の新規 source が偶然 hook/test 系で gate の対象外だった)

### 1.2 integrate skill が board の終端処理を任意にしていた

- **何をした**: `integrate/SKILL.md` Step 4 に「board.json は次 sprint まで残すか archive する」と書いた
- **何が問題だった**: ephemeral state の終端処理 (archive) を**任意**にすると、残置が default になる。しかもその残置物が 1.1 の gate 信号と衝突することを誰も検証しなかった (= state を生む skill / 消費する skill / 信号に使う hook の 3 者で lifecycle の責務が宙に浮いた)
- **観測された結果**: 実際にこの repo で「残すか」側が選ばれ、stale board が 2 週間残った

### 1.3 doctor (0.13.0) も staleness を見ていなかった

- **何をした**: 0.13.0 で採用状態 audit を作ったとき、partial の定義を「hook の物理的欠落」(配備漏れ) に置いた
- **何が問題だった**: gate が無音で効かなくなる経路は配備漏れだけではない。**配備は完全でも、gate が読む state が stale なら同じ無音**になる。coverage の概念に「hook が在るか」だけでなく「hook の信号が生きているか」が含まれていなかった
- **観測された結果**: doctor は STATUS: ok を返す状態のまま、sprint gate は死んでいた

## 2. 真因

> **ephemeral runtime state の「存在」を gate の信号にすると、state の lifecycle 終端 (完了・放棄) で gate が無音で fail-open する。** 信号は「存在」ではなく「活性」(= 未完了 task の有無) に置くべきで、かつ state の終端処理 (archive) は所有 skill の必須責務にしなければ、残置が default になり信号と衝突する。これは gate 無音化 class の 3 例目 (1 例目: advisory が忘れられて無音 → 0.12.0、2 例目: 配備漏れで無音 → 0.13.0、本件: stale state で無音) — いずれも「gate が効いているという仮定」が検証されないまま成立する点で同根。

## 3. 構造的再発防止

- [x] **gate 信号の修正**: `block-unplanned-feature-build.sh` の素通し条件を「board.json 非空」→「board.json に未完了 task (`status` ≠ `done`) が存在する」に変更。全 done / task 無し / status 不在の board は「進行中 sprint の根拠なし」として `.gate` 判定に降りる (= 解析不能は素通し側に倒さない)
- [x] **integrate skill の責務化**: Step 4 の「残すか archive する」を「**必ず** `docs/sprint/archive/<sprint>.json` へ移す」に変更 (sprint 終了 = board の終端処理まで)
- [x] **この repo の stale board を archive**: `docs/sprint/board.json` → `docs/sprint/archive/2026-05-24-hook-test-backfill.json`
- [x] **test**: 全 done board が素通しにならないこと / 未完了 (in-review 含む) task ありで素通しすること / task 無し board が素通しにならないこと / 全 done + 有効 `.gate` で通ることを pin (`tests/hooks/block-unplanned-feature-build.test.bash` 4, 4b-4e)
- [x] **memory 昇格**: `feedback_gate_signal_and_failmode` に原則 5「存在 ≠ 活性。ephemeral state を信号にするなら活性条件で読み、終端処理を所有 skill の必須責務にする」を追記

## 4. 関連 memory / docs

- `docs/incidents/2026-05-31-sprint-advisory-silent/` — class 1 例目 (advisory の無音)
- `docs/incidents/2026-06-02-coverage-drift-silent/` — class 2 例目 (配備漏れの無音)
- `docs/decisions/0002-sprint-gate-fail-closed.md` — 本 gate の設計 ADR (信号の置き場所の出所)
- memory `feedback_gate_signal_and_failmode` / `feedback_gate_distribution_coverage`
- 発見の経緯: `.bootstrap-wip` 導入の探索 (CHANGELOG `[Unreleased]`)
