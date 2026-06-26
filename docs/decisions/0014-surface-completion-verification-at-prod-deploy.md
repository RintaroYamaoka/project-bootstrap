# 0014 — 本番デプロイの瞬間に「完了照合 (逐語照合 + 再解釈はモック確認)」を表面化する

- **Status**: Accepted
- **Date**: 2026-06-26
- **Deciders**: Rintaro Yamaoka
- **References**: [0010](./0010-inject-memory-at-repeat-prone-action.md) (inject-at-action の親 — 再発しやすい行為の瞬間に記録を可視化) / [0001](./0001-subagent-hooks-not-enforced.md) (理解は強制不能 → ack/block でなく可視化) / [0013](./0013-surface-repair-vs-spec-intent-at-data-write.md) (同じ inject 機構の姉妹キー — 本 ADR は 0013:46 の「prod-deploy は opt-in のまま」を**更新**する) / [0007](./0007-verification-plan-as-merge-precondition.md) (オラクルは AI の外・「実物を見ずの完了」は継ぎ目) / appo-followup `docs/incidents/2026-06-26-premature-completion-and-misimplemented-reservation-notify.md` + `2026-06-26-asked-instead-of-executing-specific-directive.md`

---

## Context (背景)

dogfood (appo-followup) で、同一セッションに**裏表の 2 失敗**が出た。

1. **取り違えのまま完了報告 → 本番デプロイ**: ユーザーが具体的な複数文言の指示 (「{フォーム名}経由」「メール経由は{メール名}」「アポ日時追加」「対応 CV の時刻」…) を出したのに、AI は中核を**自分の都合のよい解釈に置換**し (固定ラベルを生成、対応 CV を参照せず)、各文言と実装の逐語照合をせずに **「デプロイ完了 ✅」を 2 回報告**、検証関所を置かず PR→merge→本番デプロイを 2 回実施した。誤仕様が本番稼働した。
2. **明示指示を実行せず質問で押し返した**: 別経路では逆に、明示指示に対し `AskUserQuestion` でスコープ二択メニュー (「足すか/報告のみか」) を返し、自分の実装不確実さを「指示の曖昧さ」と取り違えた。

この 2 つは矛盾でなく**同一原則の裏表**:

> 明示指示は最も忠実なフルスコープで**即実行**する (やるか/後回しか・足すか/報告かは聞かない)。`AskUserQuestion` は次の手が物理的に決まらない真の分岐だけ。**ただし自分が解釈を置換した重要機能を、取り返しのつかない本番に出す前は、二択メニューでなく具体的な出力モックで方針確認する。**

bootstrap の中心命題は **強制は自己規律でなく構造で**。だが「各文言を実装と照合したか」「これがユーザーの欲しかった出力か」は **AI が自己発行できる ack で偽装される既約な理解**なので、fail-closed な block にはできない (ADR 0001/0010)。よって ADR 0013 と同じく**可視化 (inject)** で防ぐ。決定的なのは**いつ出すか**: 取り返しのつかない一点 = **本番デプロイのコマンドが走る瞬間**。

## Decision (決定)

**`inject-action-memory` (ADR 0010) の既存 `prod-deploy` action-key に plugin 所有のデフォルト doctrine を与え、`vercel deploy --prod` 等が走る瞬間に「完了照合 + 再解釈はモック確認」を additionalContext で表面化する。** 新キー追加でも新強制軸でもなく、`prod-deploy` に既に存在したマッチャ (`action-gate.sh`) の **default memo の空欄を埋める** ADR 0013 と同型の変更。

### plugin 所有のデフォルト doctrine (普遍則 → 常時発火)

`action_default_memo prod-deploy` が registry の arm 無しでも返す文面:

> 本番デプロイは取り返しがつかない。実行前に確認: (1) ユーザーの各指示文言を 1 つずつ実装と**逐語照合**したか? 1 つでも未達なら「完了」と言うな。(2)「〜のような既存機能」の指示は、その既存機能の**実データ挙動を先に確認**したか (推測でラベル/仕様を作っていないか)? (3) 自分が**解釈を置換**した重要機能は、二択メニューでなく具体的な**出力モック**でユーザーに方針確認したか? 誤仕様のデプロイは「完了」でなく事故。

registry が `prod-deploy` を arm していれば project 固有メモ (例 deploy-author の build-env) を default の後に**追記**する (両建て = 普遍則の floor + project 知見)。

### 検出

既存のまま (本 ADR は検出を変えない): `vercel deploy` に production フラグ (`--prod`/`--production`/`prod`/`production`) が同セグメントにある時のみ `prod-deploy`。bare `vercel deploy` (preview) は非マッチ。

### Fail-mode

- **完全 advisory**: 決して exit 2 しない (ADR 0010/0001。完了照合は AI が自己発行できる ack で偽装されるので強制しない)。
- **fail-OPEN / silent**: 非 Bash / parse 不能 / 非マッチ / preview deploy。
- **射程の正直な限界**: 信号は**本番デプロイという行為**なので、(a) deploy が CI/GUI 経由で Bash を通らない経路、(b) merge も deploy もしない逐次作業での誤完了報告、は捕まえない。後者は `verification` skill の「実物を見ずの完了」継ぎ目 + 人間レビューが担う (この hook はそれを代替せず補完する)。

## Consequences (結果)

### 良い影響
- 取り返しのつかない一点で、**「各文言を照合したか・再解釈をモックで確認したか」**が目の前に出る。reservation-notify と同根の「誤仕様を完了と誤報告して本番投入」を、全 bootstrap 製 repo で機械的に表面化できる。
- ADR 0013 と同じ単一権威 (`action-gate.sh`) のまま hook と doctor が drift しない。両建てで普遍則を floor にしつつ project 固有知見も載る。

### 悪い影響 / トレードオフ・限界
- **opt-in 契約の部分緩和 (ADR 0013:46 の更新)**: ADR 0013 は「prod-deploy は従来どおり opt-in」と書いたが、本 ADR でこれを撤回し `prod-deploy` を 2 つ目の普遍 floor にする。理由 = 完了照合の教訓も project 非依存で、最危険の本番デプロイで常時出すべきだから。block せず・本番 deploy 時のみ・低頻度なので advisory bloat は小さい。残る project 固有キー (`prod-db-migrate`) は opt-in のまま。
- **強制力は無い**: 理解は既約 (ADR 0001)。AI が読んで無視する自由は残る — 設計上の選択であって穴ではない。構造で防げるのは「問いを正しい瞬間に表面化する」までで、「逐語照合をやり切る」かは人間/単一 orchestrator の frontier。
- **advisory ノイズ**: 本番 deploy のたびに出る。文面を短く・3 点に絞った。
