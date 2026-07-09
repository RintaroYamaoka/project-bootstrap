# 0017 — lane 強制を「書き込み方式」でなく「全方式が通る commit」に置き、越境編集を fail-closed にする

- **Status**: Accepted
- **Date**: 2026-07-09
- **Deciders**: Rintaro Yamaoka
- **References**: [0004](./0004-parallel-mode-integration-gate.md) (関所は特定方式の痕跡でなく全方式が必ず通る行為に置く — 本 ADR はその「書き込み方式」への適用) / [0005](./0005-ultracode-execution-engine-governed-by-bootstrap.md) (worktree 隔離と lane 不変条件、guard 1 の共有エンジン思想) / [0001](./0001-subagent-hooks-not-enforced.md) (強制できないものは可視化する) / marketing-app incident `2026-07-09-ui-leaf-producer-unwired.md` (M5) / 同 `2026-07-02-unstaged-port-merged-red-ci.md` (原因 ①: bash 編集は自動 stage されない)

---

## Context (背景)

lane 不変条件は「1 task = 1 owner = 1 worktree、自分の worktree の外を触らない」。これを守らせる関所は `block-out-of-lane-edit.sh` だけだった。だが `hooks.json` を見ると、この hook は **`Edit|Write|MultiEdit` matcher にしか登録されていない**。

つまり lane 強制は「Claude が Edit ツールで書いたとき」しか効かない。**Bash 経由の書き込みは関所を一度も通らない**:

- `biome format --write` / `prettier --write` (formatter)
- `sed -i` / `perl -pi` / codemod
- `python script.py` / `node script.mjs` が書き出す file
- `>` / `>>` リダイレクト、`patch`, `cp`

marketing-app の incident (2026-07-09, M5) で実際に踏んだ: lane worker L2 が whole-repo lint に弾かれ、**メインリポ側の未追跡ファイルを `biome format --write` で書き換えた**。どの hook も鳴らなかった。当時未追跡だったため実害は無かったが、lane の不変条件は破れていた。2026-07-02 の incident (原因 ①「bash 編集は自動 stage されず」) も同じ盲点の別の顔である。

さらに `block-out-of-lane-edit.sh` には二つ目の穴があった。worktree 外の絶対 path を「判断不能」として **明示的に fail-open** していた:

```sh
/*|[A-Za-z]:/*) exit 0 ;;   # worktree 外の絶対 path は判断不能 → fail-open
```

これは判断不能ではない。その path が**同一 repo の別 worktree の中**に在るなら、定義上 lane の外だと**確定できる**。lane worker が `/main-repo/scripts/x.mjs` を絶対 path で開けば、Edit ツール経由ですら素通りしていた。`block-uniso-main-edit.sh` は cwd がメインリポのときだけ発火するので、この経路は誰も見ていない。

## Decision (決定)

### 1. 関所を commit に置く (二層化)

**特定の書き込み方式を列挙して塞ぐのをやめる。** `--write` を塞げば `sed -i` が来る。`sed` を塞げば codemod が来る。これは whack-a-mole で、新しい方式が出るたびに無音の穴が空く。

代わりに、**全ての書き込み方式が必ず通る行為 = `git commit`** に関所を置く。`block-out-of-lane-commit.sh` (PreToolUse / Bash) は、lane worktree での commit に載る file (index、`-a` なら tracked 未 stage 変更も) が全て lane glob の中にあることを要求する。

編集時 hook は**速い feedback のため残す** (書いた瞬間に止まる方が親切)。commit hook は**取りこぼしの網**。二層構成であって置換ではない。

fail-open は根拠が無いときだけ: lane 宣言が無い (= sprint 非適用) / index が空 / 統合操作中 (merge・rebase・cherry-pick・revert は定義上 lane を跨ぐ、lead の conflict 解決)。hook 入力が parse できないときは他の commit 関所と揃えて fail-closed。

### 2. 越境編集を fail-closed にする

`block-out-of-lane-edit.sh` の worktree 外絶対 path 分岐を、
**「同一 repo の別 worktree の中 → block」「どの worktree にも属さない → 従来どおり fail-open」** に分ける。

これは bootstrap 自身の規律の回復である: **解析不能 → fail-closed / 根拠不在 → fail-open**。別 worktree の path は解析でき、違反だと分かる。`/tmp` の scratchpad や `~/.claude` は判断材料が無いので通す。

### 3. lane 判定を単一権威にする

`hooks/lib/lane-match.sh` に `lane_allows` (glob 照合) と `lane_owning_worktree` を切り出し、編集時と commit 時の両関所が**同じエンジン**を読む。二つの関所が別々に glob を解釈すると、片方だけが緩い穴になる (`detect-test-suite.sh` を test/merge 両関所で共有しているのと同じ理由、ADR 0005 guard 1)。

### 4. 配備カバレッジに載せる

`scripts/doctor.sh` の sprint 採用 REQ に `block-out-of-lane-commit.sh` を追加。vendored な `.claude/hooks/` に欠けていれば SessionStart で partial として鳴る。**配備されていない gate は効かない** — 新 gate を足して doctor に載せないのは、それ自体が silent な穴である。

## Consequences (帰結)

- lane worker が formatter / codemod を lane 外まで走らせると **commit で止まる**。対処は「対象を lane glob に絞って再実行」または「正当な scope なら lane に 1 行追記」。
- lane 外の file を `git restore --staged --worktree` で戻す運用が増える。摩擦だが、**無音で他 lane と衝突するより安い**。
- merge commit は素通しなので、統合時に lane 外の file が入ること自体は止まらない。そこは `block-unreviewed-merge.sh` と統合レビューの領分。
- **incident が挙げた対処案は採らなかった。** incident は M5 の原因を「commit gate が worktree でなくメインリポツリーで lint を走らせる構造が誘発した」と診断し、lint hook の cwd 修正を候補に挙げていた。だが lint の cwd は**動機**の話であって、**書き込みが無検査**という事実の説明ではない。lint hook を直しても `biome format --write` は依然どの関所も通らない。真因は「lane 強制が Edit ツールにしか掛かっていない」。lint hook の cwd は別件として残す (whole-repo lint が lane worker を無関係な debt で止める問題は実在するが、それは lane 強制の穴ではない)。
- 「producer が lane に含まれているか」の静的検出 (同 incident の別項) は import グラフ追跡が要り false positive が多いので、引き続き **hook 化しない**。`sprint-plan` skill の分解手順 + memory + 統合レビュー観点で担保する (ADR 0001 の系譜: 強制できないものは可視化する)。
