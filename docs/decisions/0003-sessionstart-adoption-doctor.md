# 0003 — 採用状態を SessionStart で audit する doctor を導入し、配備漏れの無音を破る

> **Extended (2026-06-19, 0.19.0)**: 同じ「可視化は強制できないが状態は surface できる」原理を **repo drift** に拡張した。SessionStart hook が採用 audit と独立に、`HEAD` の `origin/main` 遅れ (stale checkout) と merge 済み worktree の残骸 (lane 撤去漏れ) も出す。判定エンジンは `hooks/lib/repo-drift.sh`。新しい不可逆判断ではなく本 ADR の原理の適用なので独立 ADR は起こさない (drift の可視化 ≠ 強制 — どの checkout/lane が正しいかは既約)。

- **Status**: Accepted
- **Date**: 2026-06-02
- **Deciders**: Rintaro Yamaoka
- **References**: `docs/incidents/2026-06-02-coverage-drift-silent/README.md` / [0001](./0001-subagent-hooks-not-enforced.md) / [0002](./0002-sprint-gate-fail-closed.md) / memory `feedback_gate_signal_and_failmode`

---

## Context (背景)

ADR 0002 で sprint 発火判定を advisory リマインダから fail-closed gate (`block-unplanned-feature-build.sh`) に作り替えた。設計は正しい。だがその gate は **消費先 repo でその hook が現行版で実際に走っている** ことに全面依存する。

gate を「team-wide net (CI) の有無」で並べると非対称がある:

| gate | Claude-scoped (PreToolUse) | team-wide net |
|---|---|---|
| arch | ✅ | ✅ `scripts/arch-check.sh` + CI `bootstrap-arch.yml` + pre-commit |
| lint / tests | ✅ | ✅ commit-time hook |
| **sprint** (`block-unplanned-feature-build`) | ✅ | ❌ 無い |

sprint 発火は **build *前* の分解判断**なので commit-time / CI で後追い検証できない (逐次で組み終わってから並列化はできない。ADR 0002 で「commit-time は遅すぎる」として却下済)。つまり sprint gate は構造上 **PreToolUse hook 以外に backstop を持てない唯一の gate**。

実際に事故になった (incident 2026-06-02): sprint flow 採用済み (`docs/sprint/` に過去 board 多数) の repo に `block-unplanned-feature-build.sh` が未配備で、`.claude/hooks/` には 2 本だけ vendoring され settings 配線も無かった。advisory リマインダは出ていたがモデルが判定をスキップし、それを止める fail-closed の裏が**その repo には物理的に存在しなかった**。設計修正 (0002) は「現行 hook を走らせている repo」しか守らない — partial / stale な採用が**無音で成立する**ことが残った真因。

## Decision (決定)

**採用状態そのものを判定する単一エンジン `scripts/doctor.sh` を導入し、2 つの配送経路で配備漏れの無音を破る。**

doctor の verdict (STATUS 行 = machine-readable): `skip` (非 git) / `unadopted` (marker 皆無) / `declined` (unadopted + `.bootstrap-declined`) / `partial` (採用済みだが不整合) / `ok`。exit は partial=2、他=0 (CI が partial だけ fail にできる契約)。

partial の中核 = **vendored-coverage gap**: `.claude/hooks/` で vendoring しているのに採用機能 (sprint/arch/protected/lint + core) に必要な hook が物理的に欠けている状態。「宣言したのに gate が不在」= incident そのものを repo 内から検証できる。

配送経路:
- **SessionStart hook** (`bootstrap-session-doctor.sh`): session 起動時に doctor を回し、**actionable な状態のときだけ** context に注入する。`unadopted` → 導入するかを user に一度だけ尋ねる (勝手に採用ファイルを作らない / 望まなければ `.bootstrap-declined` で以後黙る)。`partial` → 不整合を警告。`ok / declined / 非 git` → 無音。
- **CI template** (`templates/ci/bootstrap-doctor.yml`): plugin 非依存。partial を bypass 不可で fail にする。

doctrine 整合: これは **advisory** である (= 強制ではない)。採用は consent 必須なので hook で強制できない。だが本プラグインが否定する advisory は「強制すべき判定を advisory に逃がすこと」であって、「強制不能な判定を**可視化する**こと」ではない。enforcement の本体は per-action gate のまま。本 hook は 0001/0002 で確立した「hook は意味的な仕事を代行できないが前進行為の precondition は強制できる」の系: 採用判断は consent ゆえ強制不能 (= 0001 の既約な残余と同類) だが、**状態を session 起動時に必ず可視化する**ことはできる。

### 採用しなかった代替案

- *SessionStart hook だけ (CI 無し)* → SessionStart は **plugin が在る session でしか発火しない**。plugin を入れず vendored hook だけの repo (= まさに incident の repo) では session audit が走らない。これでは incident の実体を救えない。CI が必須。
- *doctor を per-action の fail-closed gate にする (採用してない repo の編集を block)* → 採用は consent 案件。未採用 repo の作業を block するのは過剰 friction で、プラグインの opt-in 思想 (`.bootstrap-*` marker) に反する。可視化に留める。
- *plugin の version を repo から検証して stale を警告* → plugin は user-global で repo 内に痕跡が無く、install/版を repo から検証**不能**。根拠不在は fail-open (memory `feedback_gate_signal_and_failmode`)。ok 時に「plugin 経由は版検証不能。team-wide には vendoring / CI を」と明示するに留める。
- *未採用 repo でも毎回導入を聞く (`.bootstrap-declined` 無し)* → plugin は全 project に効くので、無関係 repo を開くたび nag する = 読み飛ばされる advisory noise に堕ちる (プラグインが最も嫌う失敗モード)。一度断られたら `.bootstrap-declined` で黙る。

## Consequences (結果)

### 良い影響

- 「採用したのに gate が届いていない」「採用も提案もされない」状態が、session 起動時 (plugin 在) と CI (plugin 非依存) の両方で**可視化**される。incident の真因 (partial の無音) が塞がる。
- doctor が単一エンジンなので、SessionStart / CI / 手動 (`bash scripts/doctor.sh`) で同じ判定が再利用できる。

### 悪い影響 / トレードオフ

- 強制できるのは「可視化」だけ。user が `.bootstrap-declined` を置けば未採用のまま進める (= consent の尊重。TDD hook が雑な test を許すのと同型のトレードオフ)。
- SessionStart hook は **plugin が在る session でしか発火しない**という射程の穴が残る。CI template が plugin 非依存で塞ぐが、CI を配線しない repo はこの穴が開いたまま (= 採用判断)。
- partial 検出は heuristic (空 marker / vendored 欠落)。plugin 経由採用の version stale は検出できない (根拠不在 = fail-open)。

### 移行後に必要な保守

- 新しい opt-in 機能 / hook を足したら doctor の必要 hook マッピング (vendored-coverage) を更新する (require-test-companion の allowlist と同じ保守点)。
