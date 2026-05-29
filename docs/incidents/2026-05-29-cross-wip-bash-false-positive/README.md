# 2026-05-29-cross-wip-bash-false-positive: cross-claude-wip が同一 session の Bash 生成物を誤って他 session WIP と判定し、有害な回避策を誘発した

`block-cross-claude-wip.sh` が、同一 session が Bash tool 経由で正規に生成・変更した file
(`npm install` の `package-lock.json` / generator 出力 / `sed -i` / `cp` / `mv`) を「当 session で
編集していない」として commit 時に `exit 2` で block した。これは誤検知だが、block メッセージが
「artifact なら .gitignore に追加するのが本筋」と助言していたため、回避策として
**`package-lock.json` を untrack、データ migration SQL をリポジトリから除外**してしまい、後で
「commit すべきものが抜けている」と発覚した (= 誤検知が有害な回避策を誘発し、リポジトリを劣化させた)。

## 関係する file / 識別子

- `hooks/block-cross-claude-wip.sh` (= cross-session WIP check。self-edited set を file 編集ツールの `file_path` だけで構築していた)
- `tests/hooks/block-cross-claude-wip.test.bash` (= 旧テストは「self-edited に無い ⇒ block」をそのまま pin し、Bash 生成物の誤検知を見逃していた)
- `package-lock.json` / migration SQL (= 回避策で誤って除外された commit すべき file)

---

## 1. ミスの一覧

### 1.1 「他 session が触ったか」を「file 編集ツールで触ったか」で代理した

- **何をした**: self-edited set を Edit/Write/MultiEdit/NotebookEdit の `file_path`/`notebook_path` だけから構築し、staged file がそこに無ければ intruder 扱い
- **何が問題だった**: Bash tool は触った file を `file_path` として transcript に残さない。判定したいのは「他 session の巻き込み」なのに、代理信号が「file 編集ツール経由か」になっていたため、npm/generator/sed/cp/mv 等の正規な同一 session 操作が巻き添えになった
- **観測された結果**: 同一 session が作った file が commit 時に block された

### 1.2 誤検知時の助言が有害だった

- **何をした**: block メッセージで「artifact なら `.gitignore` に追加するのが本筋」と案内
- **何が問題だった**: `package-lock.json` / `pnpm-lock.yaml` / `yarn.lock` / migration SQL は **commit すべき file**。gitignore/untrack すると再現性が壊れる
- **観測された結果**: 誤検知を避けるため lockfile を untrack、migration SQL を除外 → コミットすべきものが欠落

### 1.3 cry-wolf でガード自体が無効化されうる

- **何をした**: 誤検知が頻発する gate を放置
- **何が問題だった**: 誤検知が多いと user が hook を無効化し、本来防ぎたい並走 WIP 巻き込み (incident `2026-05-24`) すら防げなくなる
- **観測された結果**: gate の信頼性低下 (逆効果)

## 2. 真因

> gate の信号設計を誤った。判定対象は「他 session が編集したか」なのに、観測しやすい「file 編集ツールで触ったか」を代理信号にしたため、Bash 経由の正規操作を区別できなかった。加えて「self-edited に無い ⇒ 罪」という **guilty-until-proven-self** の既定が、根拠不在を block 側に倒していた (本 plugin の他 gate は「根拠が無ければ通す」fail-open が既定)。誤検知時の助言も、コミットすべき artifact を隠す方向で有害だった。

## 3. 構造的再発防止

- [x] **hook**: 信号を「他 session が編集したか」に反転。同一 projects dir の *他* session transcript (= 同一 working tree を共有する別ターミナル) が編集した file だけを foreign-edited とし、staged file がそこに**ある**ものだけ block。projects dir の hash は cwd 由来なので worktree 隔離下の別 session は sibling に現れず誤 block しない (= 「worktree = lane = 1 index」と構造的に一致)
- [x] **fail-open 既定**: 他 session の編集証拠が無い file は素通し。`.bootstrap-{protected,arch,lane}` 不在時の素通しと同じ「根拠が無ければ通す」原則に揃えた。コマンド解析不能時の fail-closed は不変 (= 「何の op か理解できない」だけは block)
- [x] **鮮度窓**: `BOOTSTRAP_WIP_WINDOW_HOURS` (default 24h) 内に更新された sibling のみ対象。stale session の巻き添え誤検知を防止
- [x] **助言の修正**: block メッセージから「.gitignore に追加」を削除。「lockfile / migration は commit すべき file。隠さず `git restore --staged` か worktree 分離か hook 一時 deny で対処」に差し替え
- [x] **test**: `block-cross-claude-wip.test.bash` に誤検知回帰を pin (= 同一 session の lockfile / sibling 不在の fail-open / 鮮度窓内外 / window=0 override)。incident `2026-05-24` の回帰 (foreign sibling の amend/commit block) は sibling transcript を与える形で維持
- [x] **memory 昇格**: [`feedback_gate_signal_and_failmode.md`](#) に「gate は判定対象そのものを信号にする / 根拠不在は fail-open / 誤検知時の助言で正データを隠させない」を昇格

## 4. 関連 memory / docs

- `docs/incidents/2026-05-24-shared-index-amend-mixing/README.md` — 本 hook が本来防ぐべき事故 (= 共有 index で別 session の WIP が amend に混入)。本修正はこの防御を sibling transcript 根拠で維持しつつ誤検知を除去
- `docs/incidents/2026-05-25-hook-command-parse-fail-open/README.md` — fail-open/closed をどちらに倒すかの設計判断の先例 (解析不能は fail-closed)
- memory `feedback_gate_signal_and_failmode.md` — 昇格した教訓
- CHANGELOG `[Unreleased]` — 本修正
