# 0022 — 上流工程 (要件・設計・発注・検収) を別プラグインでなく bootstrap に統合する

- **Status**: Accepted
- **Date**: 2026-08-07
- **Deciders**: Rintaro Yamaoka
- **References**: ADR 0023 (WO 完全性の関所) / ADR 0024 (下流テレメトリによる上流計測) / 旧 `upstream-process` repo / 旧 `kanban-flow` repo (`DESIGN.md` v0.12)

---

## Context (背景)

上流工程 (何を・なぜ・いつ作ってよいか) を担う独立プラグインを 2 回作り、2 回とも実運用で
定着しなかった。

**1 回目: `upstream-process`** (4 skill・20 template)。README が独立性を設計目標として明記していた:

> **非依存(重要):** この skill は bootstrap に**依存しない**。使わない現場でも単体で回る […]
> 2 プラグインは片方だけでも成立する疎結合

そしてその 2 行上でこう宣言していた:

> 判断を検出する gate は dead code になる。だから上流は hook にしない。
> skill = 必要な時にコンテキストへ載る手順書、が正しい器。

この 2 つは因果関係にある。**bootstrap から独立していたいので、bootstrap の強制層 (hook) を
使えない。使えないので advisory にするしかない。advisory は忘れられる** —
このプラグインが他所で一貫して否定している失敗モードそのもの。加えて成果物カタログ
(企画書・業務フロー図・機能一覧・非機能要件書・画面遷移図・ER 図・CRUD 表・外部 IF 一覧・
RACI 表) は実戦投入された形跡が一度も無かった。

**2 回目: `kanban-flow`** (11 skill・13 種の成果物・GitHub Projects 前提)。強制は 3 hook
持ったが、3 つとも「文書 PR を誰が承認したか」を守るもので、**引き渡し内容の完全性を見るものは
1 つも無かった**。さらに:

- 外部ボードが強制層から読めないため、`board → docs/sprint/board.json` の**同期アダプタ**を
  書く必要が生じた。これは疎結合ではなく bootstrap の内部スキーマへの無契約の依存であり、
  実際に本 repo は一度マーカー形式を変えている (`.bootstrap-<name>` → `.bootstrap/<name>`、ADR 0015)
- `/plan` との二重関門を解消するのに、相手プラグインへの変更依頼という形で 1 節を費やしていた
- CLAUDE.md を**セクション分担所有**する取り決め、incident 機構の共有交渉が必要だった
- Projects のセットアップは `updateProjectV2Field` の id 温存 rename を誤ると workflow 5 種が
  無音で無効化される。実際に 1 プロジェクトがこれで作り直しになった
- 自身の設計文書 14 節が「kanban-flow の失敗は判断ミスであり、機械的には検出できない」と
  記し、そこで自己改善ループを断念していた

利用者からの症状の報告は 3 点で、上記と整合する: **仕様の穴が埋まらない / GitHub Projects
前提が合わない / 重くて結局使わない**。

「重い」の実体は成果物の量ではなく**記憶の負担**である。利用者が保持すべき概念は
bootstrap がほぼ 0 (「普段どおり頼むだけ」) なのに対し、upstream-process が約 25
(🔴🟡🟢 / born-追認 / 幹 / ベット / appetite / 棄却条件 / 出所タグ 4 種 / 署名等級 3 種 / 軸A軸B …)、
kanban-flow が約 30 (カード型 2 / Status 6 列 / スコープ絵文字 4 / 関門 / 12 種の書き分け …)。
**bootstrap は複雑性を hook の中に隠し、上流 2 つは利用者の頭に預けた。**

## Decision (決定)

**上流工程を `project-bootstrap` の 1 サブシステム (commission) として統合する。**
独立プラグインとしての上流は今後作らない。

- 追加は skill 4 (`charter` / `order` / `pre-review` / `accept`)、hook 2、lib 1、script 1、
  template 1 セット。成果物は **WO 1 種 + charter.md 1 ファイル**に畳む (13 種 → 2 種)
- 採用マーカーは `docs/bootstrap/commission/` ディレクトリの存在。**置かなければ何も発火しない**
  (既存の opt-in 規約と同一)。したがって既存採用 repo への影響はゼロ
- 外部ボード (GitHub Projects) は採用しない。上流成果物は git 内で完結させる
- 上流の決定は**新しい強制機構を作らず既存 gate に翻訳して**効かせる:
  WO 2 節 → `.bootstrap/lane` / 3 節 → `.bootstrap/arch`・`retired` /
  8+9 節 → `docs/bootstrap/verification/<branch>.md`
- 旧 2 repo はアーカイブ表記にし、git 履歴は残す (特に kanban-flow の `DESIGN.md` は
  「なぜそうしないか」の一次資料として価値がある)

**採用しなかった代替案:**

- *3 つ目の独立プラグインを作る* — 同じ構造的選択で 2 回失敗している。強制層が別リポジトリに
  ある限り、上流は advisory に戻るか、内部スキーマへ無契約に依存するかの二択になる
- *kanban-flow を改修する* — GitHub Projects 前提と 11 skill の語彙が中核に食い込んでおり、
  「重くて使わない」の主因を残したままになる
- *bootstrap に統合しつつボードだけ残す* — 強制層はローカルファイルしか読めない。
  仕様が git の外にあると、実装した commit と diff で突合できず、hook でゲートできず、
  無音でドリフトする。将来チームに配る必要が出たら **git → Projects の一方向生成**を足す
  (同期し返さない = 正本は常に git)

**採用理由**: 本プラグインが最も嫌う失敗モードは**権威の分散**である。上流と下流を別プラグインに
割ることは、その分散を製品構造として固定していた。統合により、①の分解 (precondition の
fail-closed 強制) が上流にもそのまま適用でき、`/plan`・CLAUDE.md・ADR・incident の
所有権交渉が消える。

## Consequences (結果)

### 良い影響

- 上流の決定が bootstrap の既存 fail-closed gate によって実装中ずっと効く (新規 hook はわずか 2)
- `/plan` の二重関門を相手プラグインへの依頼でなく直接の 1 節追加で解消できた
- 利用者が保持する概念が 約 30 → 12 節 1 種類に減る
- ADR / incident / memory 昇格の機構が 1 つに保たれる

### 悪い影響 / トレードオフ

- **「bootstrap は実装専用エンジン」という説明を捨てる**。README の分界表を書き直し、
  発注から検収までの一貫規律として再定義する必要がある (本 ADR と同時に実施)
- 常時ロードされる `skills/project-bootstrap/SKILL.md` が 1 セクション増える (約 35 行)。
  実務 skill 4 つはオンデマンドなので、恒常的なコンテキスト増はこの 1 セクションに限る
- 統合の実効性はまだ**実運用で未検証**。前 2 回も設計時点では筋が通っていた。
  検証は ADR 0024 の metric (エスカレーション率・節別の偏り) で行う

### 移行後に必要な保守

- `hooks/lib/resolve-docs.sh` の冒頭コメントが「kanban-flow と兄弟になる」前提で書かれている。
  kanban-flow をアーカイブした後も `docs/decisions/` を共有ディレクトリとして扱う方針自体は
  変わらないので、文面のみ更新する
- commission を採用した repo が 1 つも無い間、この層は無音である。
  `scripts/doctor.sh` の採用 audit に含めるかは、実運用で 1 巡してから判断する
  (introspection だけで手順を書いて事故った前例に倣い、実物を 1 回通してから決める)
