# 2026-06-11-gate-broad-glob-permanent-fail-open: `.gate` の全域 glob 1 行が sprint gate を恒久 fail-open にしていた

消費先 repo (`<creative-team-app>`) の bootstrap 適用状況チェック中に発見した **顕在化済みの穴** (= 被害実在: 判定なしの新規 source が 10 本以上通過)。gate 無音化 class の **4 例目**。

`hooks/block-unplanned-feature-build.sh` は `.gate` に記録された scope glob を**無期限・無界**に信じていた。`.gate` entry は「この scope は逐次と判定した」という **feature 単位の ephemeral 判定**なのに、(a) 失効がなく (時間 unbounded)、(b) glob の広さに制約がなく (空間 unbounded)、2026-06-02 に 1 つの feature (3機能の直列実装) のために記録された `src/**` 1 行が、**それ以降の source tree 全域の gate を無音で殺していた**。

## 関係する file / 識別子

- `hooks/block-unplanned-feature-build.sh` (旧 :85-100) — `.gate` の glob を無条件に `[[ $REL == $pat ]]` で照合 (= 日付も広さも見ない)
- 消費先 `docs/sprint/.gate` 4 行目 — `src/**  supabase/migrations/**  sequential: 3機能(...)が...直列spineが支配的なため逐次(user承認済)` (2026-06-02 頃記録)
- 消費先の `.gate` 最終更新 = 2026-06-04 13:16。その後 06-05〜06-10 に `src/lib/drive.ts` / `src/lib/business-days.ts` / `src/components/CaseQuickSearch.tsx` など新規 source 10 本以上が **gate 判定なし**で作成された
- 付随: 消費先の `.gate` は template 通り gitignore 済み (= untracked で正しく運用されていた。問題は運用でなく hook の信号設計のみ)

## 1. ミスの一覧

### 1.1 gate が `.gate` entry を無期限に信じた (時間 unbounded)

- **何をした**: 0.12.0 で gate を実装したとき、`.gate` の記録を「判定済みの証拠」として期限なしで照合した
- **何が問題だった**: `.gate` entry は feature 単位の ephemeral 判定で、その feature が終われば判定の根拠も終わる。だが entry には終端がなく、**追記型 log ゆえ「所有 skill が archive する」という board.json 型の終端責務も置けない** (= 誰も「この feature は終わったから行を消す」を判定できない)。stale-board incident (2026-06-07) で「存在 ≠ 活性」を学んだ同じ週に、同じ hook のもう 1 つの信号が同じ構造で残っていた
- **観測された結果**: 06-02 の判定が 06-10 の無関係な feature を素通しさせ続けた

### 1.2 gate が glob の広さを見なかった (空間 unbounded)

- **何をした**: 「1 列目 = scope glob」とだけ定め、`src/**` のような source tree 全域の glob も有効な entry として受理した
- **何が問題だった**: gate の目的は「**新しい feature 面ごと**に sprint 判定を強制する」こと。全域 glob はその目的を定義から無効化する (= 以後のすべての feature 面が「同一 feature の継続」と誤認される)。block message 自身が例として `src/<area>/**` を提示しており、広い記録へ誘導気味だった
- **観測された結果**: TTL があったとしても、`src/**` が生きている間はすべての新規 feature が判定なしで通る状態が成立していた

### 1.3 block message が「なぜ entry が効かないか」を説明する経路を持たなかった

- **何をした**: block 時の助言は「記録して続行」のみで、`.gate` に entry が在るのに block された場合の理由提示がなかった
- **何が問題だった**: 仮に entry を不採用にする修正だけ入れると、「記録したのに block される」が無説明になり、AI が `.gate` を全消し・全域 glob 再記録などの**正データ隠蔽側の回避**に走る誘因になる (memory 原則: 誤検知時の助言で正データを隠させない)

## 2. 真因

> **per-feature の ephemeral 判定記録を gate の信号にするなら、entry は時間 (失効) と空間 (scope の広さ) の両方で bound しなければならない。** 無期限に信じれば stale-board と同じ「lifecycle 終端での無音 fail-open」が起き、無界に信じれば 1 行で gate の判定単位 (= feature 面) そのものが消える。さらに追記型 log は board.json と違い「所有 skill による終端処理」を置けないため、**state 自身に失効を埋め込む (= self-expiring)** しかない。gate 無音化 class 4 例目 (1: advisory の沈黙 → 0.12.0、2: 配備漏れ → 0.13.0、3: stale state → 0.14.0、本件: unbounded state)。

## 3. 構造的再発防止

- [x] **`.gate` 形式に日付列を追加 + TTL 失効**: `<glob>  <YYYY-MM-DD>  <理由>`。entry は記録から `GATE_TTL_DAYS` (= 3 日) で失効し、日付なし (旧形式) / 日付不正 / 未来日付は「判定の活性を証明できない」として不採用 (= 解析不能を素通し側に倒さない)。失効後は同じ行を日付だけ更新して再記録する — **その再記録が「まだ同一 feature 面か」の再判定** (= 終端処理を所有者に課す代わりに state を self-expiring にする)
- [x] **glob の広さ制約**: 有効な entry は exact path か「wildcard 前に 2 階層以上の literal prefix を持つ glob」のみ (`src/components/**` は有効、`src/**` / `scripts/**` / `**` は無効)。判定エンジンは `hooks/lib/gate-entry.sh` (`gate_date_fresh` / `gate_scope_ok`、純 bash・jq 非依存・GNU date 非依存)
- [x] **block message を構成的に**: 不採用 entry をその理由付きで列挙 (「行の削除は不要 — 失効は正常な終端」と明記) し、新形式の printf (日付込み) と scope 制約を教える。例示 glob を `src/<area>/**` → `src/<area>/<feature>/**` に変更 (= 広い記録への誘導を解消)
- [x] **test**: 単体 `tests/hooks/gate-entry.test.bash` (TTL 境界 3/4 日・未来日付・月跨ぎ・旧形式・全域 glob 9 種) + 統合 4 ケース (全域 glob 不採用 / 旧形式不採用 / 失効不採用 / block message の形式教示) を pin
- [x] **docs 正本更新**: `templates/docs/sprint/README.md` / `skills/sprint-plan/SKILL.md` / `skills/project-bootstrap/SKILL.md` / `hooks/README.md`
- [x] **消費先 remediation**: `<creative-team-app>` の旧 `.gate` を archive し、`.gate` を gitignore に追加 (template 通り ephemeral 化)、merge 済み残置 worktree (`generation-pending-status`) を撤去
- [x] **memory 昇格**: `feedback_gate_signal_and_failmode` に原則 6「per-entry の ephemeral 判定記録は時間と空間の両方で bound する。終端処理の所有者を置けない追記型 state は self-expiring にする」を追記

## 4. 関連 memory / docs

- `docs/incidents/2026-05-31-sprint-advisory-silent/` — class 1 例目 (advisory の無音)
- `docs/incidents/2026-06-02-coverage-drift-silent/` — class 2 例目 (配備漏れの無音)
- `docs/incidents/2026-06-07-stale-board-gate-bypass/` — class 3 例目 (stale state の無音)。本件はその「もう 1 つの信号」版
- `docs/decisions/0002-sprint-gate-fail-closed.md` — 本 gate の設計 ADR
- memory `feedback_gate_signal_and_failmode` / `feedback_gate_distribution_coverage`
- 発見の経緯: 消費先 repo の適用状況チェック (`.gate` の mtime 06-04 と新規 source の作成日 06-05〜06-10 の乖離から発見)
