# 0010 — 再発しやすい ACTION の瞬間に記録済み memo を注入する (inject-at-action)

- **Status**: Accepted (2026-06-25 実装、lane D2)
- **Date**: 2026-06-25
- **Deciders**: Rintaro Yamaoka
- **References**: deploy-author bug が同一 fix を memory に持ちながら ~7 回再発した実体験。`docs/decisions/0001-subagent-hooks-not-enforced.md` (理解は強制不能 / ack token は被 gate 当事者が自己発行できる)。`hooks/lib/merge-targets.sh` / `hooks/lib/protected-branch.sh` (string-proxy を殺す共有トークナイザの先例)。memory `feedback_gate_signal_and_failmode` (信号選び・fail-mode) / `feedback_gate_distribution_coverage` (関所は全方式が通る行為に置く)。`skills/incident/SKILL.md` (memory 昇格の責務)。

---

## Context (背景)

memory に **正しい fix が記録されていても、それが効くのは「次の session 開始時に AI が読む」ときだけ**で、実際にその操作を打つ瞬間には目の前に無い。結果、ある repo の prod deploy で「deploy author を渡し忘れる」型の bug が、その fix を documenting した memory が存在するのに **~7 回再発した**。session を跨ぐたびに、関係する memory が文脈に載らないまま同じ操作に到達してしまう。

これは新しい block 条件を足せば直る種類の問題ではない。

1. **理解は強制不能** (ADR 0001): 「memo を読んだ」ことの ack/block token は、まさに gate される当事者 (= deploy を打つ AI 自身) が自己発行できる。だから ack を precondition にしても素通りする。強制できるのは「前進行為に precondition を課す」場合だけで、ここで課せる前進行為が無い (deploy を止める根拠は無い — fix を**忘れている**だけで、deploy 自体は正当)。
2. 一方、**可視化なら効く**。fix が目の前に出ていれば、忘れていた当事者がそれを適用できる確率は大きく上がる。問題は「強制」ではなく「想起のタイミング」。

つまり必要なのは **block ではなく、操作の瞬間の visibility** である。

設計上の罠が 2 つある:

- **マッチャをどう書くか**。「この操作か?」の判定を registry の各行に user 正規表現で書かせると、`.*deploy.*` が `echo deploy` に当たる / 未アンカーの `git` が `legit` に当たる、といった **未レビューの greedy-match / string-proxy 事故** (merge-targets.sh / protected-branch.sh が殺したのと同じ bug class) を、消費先 repo ごとに再生産することになる。
- **TTL の極性**。armed entry に期限を付けると、期限切れが「黙って disarm = memo が出なくなる」方向に倒れると、最も再発を抑えたい古い armed ほど無音で効かなくなる (= self-disarming silence、`feedback_gate_signal_and_failmode` の終端所有問題と同根)。

## Decision (決定)

repeat-prone な ACTION の **PreToolUse(Bash) の瞬間に、記録済み memo を additionalContext として注入する** hook を入れる。block しない・ack も取らない・**決して exit 2 しない**。

### 1. inject-at-action (block でない)

`hooks/inject-action-memory.sh` は command をパースし、共有トークナイザでマッチし、opt-in registry が当該キーを arm していれば memo を `hookSpecificOutput.additionalContext` (他の context 注入 hook = `bootstrap-session-doctor.sh` と同形) として出して **exit 0**。それ以外 (パース不能 / キー未一致 / registry 不在 / 当該キー未 arm) はすべて **exit 0 silent**。

これは「強制を 4 つの設計判断に作り替える」の ② (信号選び) の visibility 版であり、**強制 (precondition) ではない**。ADR 0001 の「理解は irreducible」に正面から従う。

### 2. controlled-vocabulary なマッチャ (per-entry regex でない)

マッチャは **共有 plugin code** `hooks/lib/action-gate.sh` のトークナイザ + **CLOSED な plugin 所有の ACTION-KEY enum** (`ACTION_KEY_ENUM` = 現状 `prod-deploy` / `prod-db-migrate`)。merge-targets.sh と同じ正規化を踏む: 先頭の `FOO=bar` env-prefix 除去 / path-prefixed バイナリ (`/usr/local/bin/vercel`) 受理 / `npx <bin>` / `bash -c "..."` ランチャの unwrap / compound 全 segment の walk / noglob word-split。

消費先 (incident 著者) は **enum からキーを選ぶだけ**。registry は既存キーを **arm するだけ**で、マッチ条件は書けない。enum を増やす = `action-gate.sh` のキー + matcher arm + test を足す **reviewed な plugin-level 変更**で、消費先のインライン正規表現には決してしない。これで未レビュー matcher の事故 class を構造的に締め出す (単一権威: hook と doctor は同じ lib を source するので「何が有効キーか」で drift しない)。

### 3. registry は opt-in marker

repo root の `.bootstrap-actions` (雛形 `templates/bootstrap-actions.example`)。1 行 = `<action-key> | <memory-slug-or-path> | <note>`。**無ければ injector は完全に無音** — 採用していない repo は一切撹乱されない (`feedback_gate_signal_and_failmode` の「根拠不在 = fail-open」)。

### 4. doctor が arm 漏れ / orphan を可視化 (surface only)

`scripts/doctor.sh` に `actions:` 行を足す: registry の有無 + **orphan** (enum に無いキーを arm = memo が永遠に発火しない死に entry) + **arm 漏れ** (`docs/incidents` に `repeat-action` タグの記録が在るのに registry 不在 = fix を記録したが再surface を arm していない、まさに本 incident の穴) を列挙する。**status は flip させない / exit 2 もしない** (surface only)。

### 5. incident skill に arm を組み込む

`skills/incident/SKILL.md` の再発防止チェックリストに「操作型の再発なら action-key を arm する」を追加。incident → memory → **arm** までを責務に含め、書きっぱなしを防ぐ。

## Fail-mode (どちらに倒すか)

**全面 fail-OPEN / silent**。この hook は何も block しないので、**fail-CLOSED にすべき不安全な側が存在しない**。block する gate (merge / push / commit) は malformed payload で不安全操作を通さぬよう fail-CLOSED にするが、ここは「memo が出ないだけ」で害が無いので逆。具体的に fail-open にするのは: command パース失敗 / トークナイズの mis-split (quote 内 separator など merge-targets.sh と同じ既知限界) / enum キー未一致 / registry 不在 / 当該キー未 arm — すべて exit 0 silent。

**TTL は SAFE-side に倒す (本 ADR の明示判断)**。armed entry に self-disarm な期限を **付けない**。仮に将来期限を付けるなら、期限切れは「黙って disarm」ではなく **再surface (louder)** に倒し、doctor が「expiring/expired な armed entry」を列挙する。armed entry が無音で効かなくなる方向 (= 最も再発を抑えたい古い arm が黙って死ぬ) は禁止。これは `gate-entry.sh` の TTL が「期限切れ = 関所が黙って開く」を直した教訓 (`docs/incidents/...gate-broad-glob-permanent-fail-open`) の極性を、visibility 文脈に合わせて反転させたもの: 関所では期限切れ→閉じる (安全)、想起では期限切れ→より目立つ (安全)。

## Consequences (結果)

### 良い影響
- memory に記録済みの fix が、その操作の瞬間に目の前に出る。「記録したのに想起されない」空白 (deploy-author の ~7 回再発) を埋める。
- マッチャが単一の reviewed plugin code に集約され、消費先が未レビュー正規表現で string-proxy 事故を再生産する経路を塞ぐ (③ 可視化 + 単一権威)。
- block でないので誤検知のコストが「余分な advisory 1 個」に留まる (cry-wolf で guard 全体を無効化されない)。

### 悪い影響 / トレードオフ / 文書化した限界
- **CLOSED enum ゆえ表現力が低い**: 雛形に無い操作は arm できず、plugin への reviewed 追加が要る。これは意図的なコスト (未レビュー matcher を許さない対価)。新操作の需要は doctor の arm 漏れ可視化と incident skill 経由で plugin に集約される。
- **理解は依然 irreducible**: 注入しても読まない・適用しない自由は残る (ADR 0001)。本機構は確率を上げるだけで保証ではない。
- **トークナイズの既知限界** (merge-targets.sh 同様): quote 内の separator metacharacter は full shell parser 無しに実 separator と区別できず、その 1 入力で memo を取り逃しうる (fail-open — 誤 block は起こさない)。`bash -c "..."` は de-quote 後にインライン展開して script の先頭語を head 扱いする近似で、単発 verb のキーには十分だが任意の入れ子 shell を完全網羅はしない。
- **registry の arm/disarm 終端所有者は人間** (incident skill が arm を促し、doctor が孤児/漏れを surface する)。完全自動の終端処理は持たない — opt-in な人手記録なので、TTL を付けないことと doctor の可視化でこれを bound する。
