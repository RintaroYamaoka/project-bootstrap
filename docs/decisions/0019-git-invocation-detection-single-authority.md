# 0019 — git 呼び出し検出の単一権威と、列挙不能な push の fail-closed 化

- **Status**: Accepted
- **Date**: 2026-07-10
- **Deciders**: Rintaro Yamaoka
- **References**: [0017](./0017-lane-enforcement-at-commit-chokepoint.md) (関所は全方式が必ず通る行為に置く) / [0018](./0018-lint-gate-signal-is-the-commit-not-the-tree.md) (gate は判定対象そのものを信号にする) / [0005](./0005-ultracode-execution-engine-governed-by-bootstrap.md) guard 1 (共有エンジンで判定の drift を防ぐ) / memory `feedback_gate_signal_and_failmode` (解析不能=fail-closed・根拠不在=fail-open)

---

## Context (背景)

2026-07-10 の全体監査で、Bash gate の git コマンド検出に**系統的なすり抜け穴**が実測確認された (すべて実コマンドで再現済み):

1. **git グローバルオプション**。全 detector regex は `git` の直後に subcommand を要求するため、`git -C /repo push origin main` / `git -c k=v push …` / `git --git-dir=.git push …` / `git -P push …` を**すべて見逃した**。`block-push-to-protected.sh` は exit 0 で保護 push を素通しした (P0)。tokenizer (`push_destination_branches`) も `push` の直前トークンが `git` のときしか arm せず、destination を 1 つも出さなかった。
2. **path-prefix の未展開**。push/merge 側は過去の修正で `/usr/bin/git` を許容済みだったが、commit 系 gate 5 本 (test / lint / arch / lane / cross-wip) の共有 pattern には展開されておらず、`/usr/bin/git commit` / `./git commit` が全 gate を素通りした。
3. **`git push --all` / `--mirror`**。refspec 列挙が `-*` arm でこれらを握り潰して destination 0 件になり、gate は current branch 判定に落ちる。feature branch 上から `git push --all origin` すると、**保護された local main が素通りした** (P0)。

1 と 2 は「文字列 proxy を gate 信号にした」既知のバグ類 (merge-targets.sh / protected-branch.sh が同型を 2 度潰している) の**3 度目の再発**である。regex を hook ごとに継ぎ足す限り、新しいオプション・新しい書き方が出るたびに同じ穴が開く。

## Decision (決定)

### 1. git 呼び出し検出を単一権威 `hooks/lib/git-invocation.sh` に集約する

「このコマンドは `git <subcommand>` を呼ぶか」の判定を regex でなく **tokenizer walk** にする: shell separator を pad して分かち書き → 各 segment で `git` / `*/git` head を見つける → **git グローバルオプションをスキップ** (値を取る `-C` / `-c` / `--git-dir` / `--work-tree` / `--namespace` / `--config-env` / `--attr-source` は次トークンごと、その他の `-…` は flag として) → 最初の非オプショントークンが subcommand。

- `cmd_invokes_git_subcommand <cmd> <sub>` — 検出の唯一の入口。commit 系 gate 5 本、`cmd_has_git_push` (protected-branch.sh)、`cmd_has_git_merge` (merge-targets.sh) が全てこれに載る。
- `git_subcommand_arglines <cmd> <sub>` — segment ごとの引数列を返す。push/merge の refspec/target 抽出、`block-add-all.sh` の add/commit/stash 判定がこれを使う (greedy sed の残存も同時に廃止)。
- **未知の `-…` オプションは検出側に倒す** (= git 自身がエラーにするコマンドを gate が検出しても害がない。blocking gate の曖昧さは fail-closed 側に置く)。

### 2. 列挙不能な push は fail-closed (`--all` / `--branches` / `--mirror`)

これらの push は refspec を持たず、destination 集合は「全 local branch」(mirror は全 ref) である。コマンド文字列からは列挙できないので、**caller が `git for-each-ref refs/heads/` で展開し、1 つでも protected な branch があれば block する** (`push_pushes_all_branches` + gate 側展開)。

これは gate の約束の変更である: 旧実装は「refspec が無ければ current branch を見る」に落ち、`--all` を実質 fail-open にしていた。新実装は**破壊 scope が列挙不能なら列挙を自分で展開して止める**。設計原則は「解析不能 = fail-closed」— `--all` は解析不能ではなく「全部」と解析できるのだから、全部を判定する。`block-stale-write-to-protected.sh` (trunk freshness gate) も同じ扱い (local trunk が存在すれば trunk push と判定)。

### 3. 検出の曖昧さの代償 (正直に明示)

- quoted 引数の中の separator / `git <sub>` 列は full shell parser なしには区別できない (既知限界、merge-targets.sh と同じ)。誤検出方向は **over-detect** (= commit message 中の "git commit" が gate を arm する) で、blocking gate では安全側。
- `echo git commit` のような「引数としての git」も arm する (旧 regex と同挙動)。素通し側に倒さない。

## Consequences (帰結)

- **検出ロジックの再発クラスが 1 ファイルに閉じた。** 新しい書き方 (新グローバルオプション等) への追随は git-invocation.sh の 1 箇所を直せば全 gate に効く。
- **`git push --all origin` で保護 branch を運べなくなった。** 全 local branch 展開により、意図的に全 branch を push したい場合も protected branch を含む限り block される — それは仕様 (protected への push は PR 経由)。/permissions での一時 deny が正規の bypass。
- commit 系 gate は subshell (`(git commit)`) やグローバルオプション形も捕まえるようになり、検出は旧 regex より広い (over-block 側の変化のみ)。
- 本 ADR の gate 約束変更 (--all fail-closed 化) は 2026-07-10 の全体監査で設計者が修正方針 (--all の全 branch 扱いを含む) を提示済みの上で「全評価★5化を計画・実装・リリースせよ」と明示指示したことで承認されている (verification plan の `by=human` 行)。
