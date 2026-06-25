# 0009 — stale な checkout からの trunk push を freshness gate で止める

- **Status**: Accepted (実装済み)
- **Date**: 2026-06-25
- **Deciders**: Rintaro Yamaoka
- **References**: `docs/incidents/2026-06-16-prod-migration-from-stale-checkout` / `docs/incidents/2026-06-25-stale-staged-commit` / [0003](./0003-sessionstart-adoption-doctor.md) (drift advisory の出自) / [0007](./0007-verification-plan-as-merge-precondition.md) / `hooks/block-push-to-protected.sh` / `hooks/lib/repo-drift.sh` / memory `feedback_gate_signal_and_failmode`

---

## Context (背景)

stale-checkout class の本番化事故が 2 件続いた。どちらも `git status` clean を「on latest trunk」と誤読したのが根:

- **2026-06-16-prod-migration-from-stale-checkout**: `origin/main` より **24 commit 遅れ**た checkout から prod migration を実行。status clean を最新 main と信じ、古いロジック/schema で本番を汚した。
- **2026-06-25-stale-staged-commit (rebase-drops-deploy)**: remote が進んでいるのに stale な local main から trunk へ push し、整合化で remote 側の commit を**取りこぼした**。

この class はこれまで `hooks/lib/repo-drift.sh` のヘッダに **コメントとしてしか存在しなかった** — SessionStart の drift advisory (`drift_report` が behind を可視化) は判断を人間に委ねるので、操作の瞬間 (migration 実行 / trunk push) は何も止めない。advisory は consent/判断を強制できない (ADR 0003 の doctrine) ので、忙しい運用では読み飛ばされる。

問い: この class のどこを enforceable な precondition に作り替えられるか。任意の prod script (`tsx migrate.ts`) は「この checkout が stale だ」を結ぶ**決定論的 trace を持たない** ので、止めるには「今この操作は本番に効くか」という既約な判断が要る — 強制できない。だが **trunk への `git push`** は決定論的に観測できる行為で、freshness (= fetch 後の behind 数) も決定論的に測れる。ここだけを gate にする。

## Decision (決定)

### 1. 信号は「trunk への git push」という行為 + 物理 trace (fetch 後 behind > 0)

文字列 proxy ではなく **行為そのもの**を信号にする (move ②)。push 先 branch が **trunk** に一致するときだけ対象にする。trunk の定義は `hooks/lib/repo-drift.sh` の `drift_main_ref` が解決する remote-tracking ref (`origin/main` → `main`、`origin/master` → `master`) を `<remote>/<branch>` に分解したもの。push destination の列挙は `lib/protected-branch.sh` の `push_destination_branches` / `cmd_has_git_push` を再利用し、compound command・path-prefixed git・`src:dst`・`+force`・`refs/heads/` prefix・refspec 無し (暗黙 current branch) を全てカバーする。

freshness 判定は `lib/repo-drift.sh` に新設した `fetched_behind_count <dir> <remote> <branch>`: 明示 refspec + timeout 付き fetch (`git -C <dir> fetch --quiet <remote> +refs/heads/<branch>:refs/remotes/<remote>/<branch>`、`timeout` があれば使い無ければ素で) を**先に**行ってから `git rev-list --count HEAD..<remote>/<branch>` で behind を返す。fetch 失敗は **distinct な non-zero return** で signal する。

### 2. block-push-to-protected との非重複と順序 (ADR の核心)

この gate は `hooks/block-push-to-protected.sh` の**重複ではなく直交**する:

- **block-push-to-protected** は **PR-FLOW** を opt-in `.bootstrap-protected` で強制する。宣言された保護 branch への**直接 push を outright で block** する (freshness は無関係)。
- **本 gate** は otherwise-**allowed** な trunk push の **freshness** を強制する。信号は `drift_main_ref` が解決する trunk であって `.bootstrap-protected` membership では**ない**。

`.bootstrap-protected` に key を置くと **両方の問題**が起きる: (a) PR-flow gate を**二重化**し、(b) trunk を正当に直 push する repo (例: **本プラグイン自身の release flow** — `.bootstrap-protected` を持たない) で**発火しない**。だから signal を分けた。

**順序**: 本 gate は block-push-to-protected の **後**に走る。trunk を保護している repo では直 push はそちらで既に止まる。本 gate は、あちらが意図的に許す「`.bootstrap-protected` 無しの直接 trunk push」を freshness で守る net。

### 3. 単一権威 (online / offline の drift 防止)

staleness の判定は `lib/repo-drift.sh` に集約する。offline の `behind_count` (SessionStart doctor 用、no-fetch のまま据え置き) と online の `fetched_behind_count` (本 gate 用) を **同じ lib の隣り合う関数**にし、「behind とは何か」を online/offline で 1 本の権威に保つ — gate 信号の drift は本 repo が first-class bug 扱いする silent-bypass class なので、別ファイルに第二定義を置かない。`behind_count` は doctor の no-network 契約を守るため**触らない** (fetch を畳み込むと doctor の hot path に誤って network が乗る)。

## Fail-mode (deliberate)

- **parse 不能 = fail-CLOSED (exit 2)**。BLOCKING gate が入力を読めないなら push を通さない (`parse_command` の契約どおり)。
- **fail-OPEN (exit 0)** — block しかけたときだけ stderr で announce し、無音 no-op にはしない — を次のすべてで取る: 非 git push / git も work-tree も無い / trunk ref が解決不能 / destination が trunk でない / fetch 失敗・timeout (offline / no remote / auth fail) / behind == 0。理由: 根拠不在 = fail-OPEN で**非対象 repo と offline を一切妨げない**。network 不通が work を止めることは**絶対に**あってはならない。
- **BLOCK (exit 2)** は **trunk push + fetch 成功 + behind > 0** のときだけ。

### 決定論的 trace を持たない sibling の非 gating (documented limit)

任意の prod script (`tsx migrate.ts`、deploy コマンド等) は「この checkout が stale だ」に結ぶ決定論的 trace を持たない。止めるには「この操作は本番に効くか」という既約な判断が要り、強制すれば誤検知で cry-wolf になる (ADR 0008 #2 / 2026-05-29 false-positive incident と同じ罠)。よってこの class は gate せず、**SessionStart の drift advisory** (`bootstrap-session-doctor.sh` + `drift_report`) が session 開始時に behind を可視化する側に残す。本 gate は決定論的に書ける `git push` だけを enforce する。

## Consequences (結果)

### 良い影響
- stale-checkout class の二事故が、コメントから enforceable な precondition に昇格した。trunk push という決定論的行為に freshness を課すことで、「古いロジックで汚す」と「進んだ分を落とす」の両方向の害を 1 gate で塞ぐ。
- staleness の判定が online/offline で単一権威になり、gate と doctor が drift しない。

### 悪い影響 / トレードオフ
- 本 gate は唯一 **fetch (network) を行う PreToolUse gate**。timeout で bound し失敗を fail-open にしているが、trunk push のたびに最大 10s の fetch が乗る。trunk push は稀な操作なので許容するが、頻発する運用が出たら計測 (④) して再考する。
- quoted separator を含む push 引数 (`git push -o "a && b" origin main`) は `protected-branch.sh` の known limit どおり mis-split しうる (その 1 入力だけ fail-open)。commit-time の test/arch gate と CI が net。
- 任意 prod script は依然 advisory 止まり (決定論的 trace 不在の既約な残余)。gate ではなく drift_report の可視化に委ねる。

### 移行後に必要な保守
- 新 hook の wiring (`hooks/hooks.json` への PreToolUse(Bash) 登録) は lead が統合時に行う (本 lane では触らない)。
- `timeout` 不在環境では fetch が wall-clock で bound されない — hung host で gate が待つ可能性がある。最小環境向けの代替 bound が必要になったら別途検討する (現状は `timeout` 前提を README に記載)。
