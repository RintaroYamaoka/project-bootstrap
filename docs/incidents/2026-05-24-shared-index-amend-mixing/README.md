# 2026-05-24-shared-index-amend-mixing: 共有 index で別 session の WIP が --amend に混入し origin/main へ push された

propagate-ai の実運用で、複数の Claude を**同一 working tree (= 共有 `.git/index`) を共有する複数ターミナル**で並走させていた。Terminal A が docs + tests 計 14 file を stage していたところに、別ターミナルの `git commit --amend` がその共有 index を巻き込み、commit `67c2bad` に **A の中身 + 別のメッセージ**が混入。さらにそれが `origin/main` へ push され lock-in した。

## 関係する file / 識別子

- `hooks/block-cross-claude-wip.sh` (= cross-session WIP check。`--amend` を除外していた)
- `hooks/block-dangerous-git-ops.sh` (= destructive op block。通常 push は対象外)
- commit `67c2bad` (= 混入した commit) / `origin/main` (= push 先)

---

## 1. ミスの一覧

### 1.1 共有 index 構成で並列 Claude を走らせた

- **何をした**: 同一 working tree を複数ターミナルの Claude で共有 (= `.git/index` を共有)
- **何が問題だった**: 一方の stage 操作が他方から見える。amend/commit が互いの staged を巻き込む土壌
- **観測された結果**: A の 14 file が別 session の commit に混入

### 1.2 `git commit --amend` が他 session の staged を巻き込んだ

- **何をした**: 別ターミナルで `git commit --amend`
- **何が問題だった**: amend は現在 index の全 staged を直前 commit に畳み込む。共有 index では A の staged も対象
- **観測された結果**: `67c2bad` が A の docs+tests + 誤メッセージで再構成された

### 1.3 混入 commit が origin/main へ直接 push された

- **何をした**: `git push` (feature branch + PR を経ず main へ)
- **何が問題だった**: 共有ブランチに不可逆に lock-in。巻き戻しに race が発生

## 2. 真因

> 並列 Claude 支援が「防御 (bulk-stage / destructive op の block)」止まりで、(a) `--amend` が cross-session check の**除外穴**、(b) `main` 直 push に **gate 不在**、(c) そもそも**共有 index 構成を許容**し worktree 物理隔離を default にしていなかった。3 つが重なって事故が成立した。

## 3. 構造的再発防止

- [x] **hook**: `block-cross-claude-wip.sh` の `--amend` 丸ごと除外を撤廃 (= 共有 index では amend が最も巻き込む経路)。message-only amend は staged 空で素通し
- [x] **hook (新)**: `block-push-to-protected.sh` — `main`/`master` 直 push を block、feature branch + integrate 経由に矯正
- [x] **substrate (新)**: `block-out-of-lane-edit.sh` + `.bootstrap-lane` + `sprint-plan` skill で **worktree = lane = 1 index** を sprint の default 化 (= 共有 index 事故を構造的に不可能にする)
- [x] **test**: `tests/hooks/block-cross-claude-wip.test.bash` に 1.2 の回帰テストを pin。dogfood (4 worktree 並列) でこの構成の安全性を実証
- [x] **memory 昇格**: [`reference_propagate_ai_incidents.md`](#) にこの事故を記録、[`feedback_bootstrap_is_canonical.md`](#) に「project-local 宣言で受ける」方針

> 副産物: 上記 hook 群に bash テストを整備した dogfood が、既存 hook の実バグ 3 件 (`git clean -fd`/`-fx` 見逃し / `git stash push -m -- path` 過剰 block / commit hook の runner 不在ガード欠落) を捕獲した。テスト不在の hook は「謳い文句どおり動く」保証が無いことの実例。

## 4. 関連 memory / docs

- `reference_propagate_ai_incidents.md` — 本事故を含む propagate-ai 事故記録 (project-bootstrap 改善の実例ソース)
- `feedback_bootstrap_is_canonical.md` — project 固有事情は `.bootstrap-arch` / `.bootstrap-lane` で受ける
- CHANGELOG `0.7.0` — 本 incident を起点とした並列開発フロー + 依存方向強制の追加
