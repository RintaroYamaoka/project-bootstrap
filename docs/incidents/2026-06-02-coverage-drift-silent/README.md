# 2026-06-02-coverage-drift-silent: fail-closed gate を作ったのに消費先 repo に未配備で、判断ミスを止める裏が無かった

実アプリ開発の repo (sprint flow 採用済み = `docs/sprint/` に過去 board 多数) で feature 実装に着手したとき、3 ゲート (① feature ② 非重複 leaf ≥2 ③ lane ≤ wip_limit) を全て満たすのに、モデルが sprint 自動分解をスキップして逐次に突入した。「君のミスか bootstrap のバグか」と問われて切り分けたところ:

- **判断ミスはモデル**: UserPromptSubmit の advisory リマインダで「コードに触れる前に sprint 発火判定を必ず行う」と明示が出ていて、3 ゲート全通過だったのに、TDD hook / 共有 worktree のリスク / パターン追従の確実性を理由に逐次を選んだ。判定スキップは弁解の余地なし。
- **ただし止める裏が無かった**: 本来 fail-closed で止めるべき `block-unplanned-feature-build.sh` (ADR 0002, 0.12.0) が **その repo に未配備**。`.claude/hooks/` には `require-test-companion` と `block-commit-if-tests-fail` の 2 本だけが vendoring され、settings 配線も無かった。advisory は出たがモデルが無視し、ハードな gate が物理的に存在しなかった。

## 関係する file / 識別子

- `hooks/block-unplanned-feature-build.sh` (= ADR 0002 / 0.12.0 で追加した fail-closed gate。設計は正しい)
- 消費先 repo の `.claude/hooks/` (= 2 本だけの partial vendoring。plugin も現行版ではなかった)
- `hooks/sprint-trigger-reminder.sh` (= 出ていた advisory。モデルが無視した)

---

## 1. ミスの一覧

### 1.1 モデルが 3 ゲート全通過の判定をスキップした

- **何をした**: advisory リマインダを読んだ上で、逐次の方が確実という自己正当化で sprint 分解を回さなかった
- **何が問題だった**: 強制すべき判定を「自分の判断」で advisory 扱いした。これは ADR 0002 で fail-closed 化したはずの失敗モードの再演
- **観測された結果**: feature が逐次 TDD に流れ、並列分解されなかった

### 1.2 fail-closed gate が消費先 repo に届いていなかった (真の構造穴)

- **何をした**: 0.12.0 で gate を作り、bootstrap 本体には配線したが、消費先 repo へは古い / 部分的な vendoring しか入っていなかった
- **何が問題だった**: gate の設計は正しくても、**消費先 repo でその hook が現行版で走っていなければ効果はゼロ**。とりわけ sprint 発火 gate は build 前の判断で CI 後追いができず、PreToolUse hook 以外に backstop を持てない (ADR 0002)。配備漏れが致命的になるのに、その漏れを検知する機構が無かった
- **観測された結果**: モデルのミスを止める裏が物理的に不在で、advisory 無視がそのまま事故になった

## 2. 真因

> fail-closed gate の設計修正 (ADR 0002) は「現行 hook を走らせている repo」しか守らない。だが **採用したのに gate が届いていない (partial) / 採用も提案もされない (unadopted) 状態が無音で成立する**経路が残っていた。arch には CI net があるが sprint gate には無いため、配備漏れを誰も検知できず、唯一の backstop が一番必要な局面で repo に存在しなかった。「設計が正しい」と「配備されている」は別問題だった。

## 3. 構造的再発防止

- [x] **engine**: `scripts/doctor.sh` を新設。採用状態を `skip/unadopted/declined/partial/ok` に判定。partial の中核は **vendored-coverage gap** (= `.claude/hooks/` で vendoring しているのに採用機能に必要な hook が欠落 = 本 incident そのもの) で、repo 内から検証できる。exit は partial=2 (CI 用契約)
- [x] **SessionStart hook**: `hooks/bootstrap-session-doctor.sh` を新設。session 起動時に doctor を回し、unadopted → 導入を一度だけ尋ねる / partial → 配備漏れを警告 / ok・declined・非 git → 無音。plugin が在る session で「採用状態が無音」を破る
- [x] **CI template**: `templates/ci/bootstrap-doctor.yml` を新設。SessionStart は plugin が在る session でしか発火しない (= まさにこの repo は plugin 非現行で救えない) ため、plugin 非依存の CI が partial を bypass 不可で fail にする
- [x] **nag 制御**: 未採用 repo を毎回 nag しないよう `.bootstrap-declined` で opt-out (= advisory noise に堕ちて読み飛ばされるのを防ぐ)
- [x] **ADR**: 設計を `docs/decisions/0003-sessionstart-adoption-doctor.md` に記録 (採用しなかった SessionStart 単独 / per-action block / version 検証 / 毎回 nag も明記)
- [x] **test**: `tests/hooks/doctor.test.bash` + `tests/hooks/bootstrap-session-doctor.test.bash` で skip/unadopted/declined/partial/ok と vendored-gap / 無音条件を pin
- [x] **version**: 0.13.0 (13 hook)、memory `feedback_gate_distribution_coverage` に昇格

## 4. 関連 memory / docs

- `docs/decisions/0003-sessionstart-adoption-doctor.md` — 本修正の ADR
- `docs/decisions/0002-sprint-gate-fail-closed.md` — gate 設計 (sprint に CI net が無い既約性の出所)
- `docs/incidents/2026-05-31-sprint-advisory-silent/README.md` — gate を生んだ先行事故 (advisory の沈黙)
- memory `feedback_gate_signal_and_failmode` / `feedback_gate_distribution_coverage`
- CHANGELOG `[Unreleased]`
