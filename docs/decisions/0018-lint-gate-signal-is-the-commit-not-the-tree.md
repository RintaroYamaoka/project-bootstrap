# 0018 — lint gate の信号は「ツリー全体」でなく「この commit が運ぶ file」

- **Status**: Accepted
- **Date**: 2026-07-09
- **Deciders**: Rintaro Yamaoka
- **References**: [0017](./0017-lane-enforcement-at-commit-chokepoint.md) (lane 強制を commit 関所へ。本 ADR はその宿題) / [0005](./0005-ultracode-execution-engine-governed-by-bootstrap.md) guard 1 (共有エンジンで判定の drift を防ぐ) / marketing-app incident `2026-07-09-ui-leaf-producer-unwired.md` (M5)

---

## Context (背景)

`block-commit-if-lint-fails.sh` は `npm run lint` / `ruff check .` 等を **cwd で・ツリー全体に対して** 走らせていた。

incident は M5 の構造要因を「commit gate が **worktree ではなくメインリポツリー**で lint を走らせる」と記述したが、**この診断は不正確**である。実査 (一時 repo + lane worktree で再現) の結果:

- lint は cwd = lane worktree の中で走る。メインリポツリーでは走らない。
- 真の欠陥は **whole-tree lint** であること。git worktree には repo の全 tracked file が複製されるので、lane worktree にも他 lane の file・既存の lint debt がそのまま在る。

再現: lane が `src/auth/**` だけを所有し、自分の file だけを stage して commit すると、**lane が所有しない `DEBT.js` の lint 失敗で `exit 2`** される。lane worker には lane の中に正当な remedy が存在しない。直すには lane を出るしかない。

**gate が違反の動機を作っていた。** 実際 L2 は `biome format --write` で lane 外を書き換えた (ADR 0017 で塞いだ越境編集の、動機側の原因)。

これは「gate は判定対象そのものを信号にする」の違反である。判定対象は **この commit** であって、ツリーの歴史的 debt ではない。

## Decision (決定)

### 1. 信号を commit が運ぶ file に絞る

lint gate は `git diff --cached --name-only` (+ `-a`/`--all` なら未 stage の tracked 変更) が返す file だけを lint する。削除された file は渡さない (linter が存在しない path でエラーになる)。その linter が扱う拡張子でない file も渡さない。

この commit がその linter の扱う file を 1 つも運ばないなら、判定対象が無いので素通し。

### 2. scope できない linter は whole-tree のまま fail-closed で残す

全 linter が file 引数を取れるわけではない (`golangci-lint run` / `cargo clippy` は package 単位)。**取れないものは緩めない** — 従来どおりツリー全体を検査して block する。ただしメッセージで「失敗が lane の外の file 由来なら、それを直しに lane を出るな。lead に上げろ」と明示する (越境編集は ADR 0017 の gate が物理的に止めるので、案内と強制が一致する)。

`npm run lint` は script 文字列から tool を同定して scope する。**既知の tool (`eslint` / `biome` / `oxlint` / `prettier`) だけ**を path 対応と認め、`next lint` のように file 引数で意味が変わるものは同定せず whole-tree に落とす — 誤って scope すると**存在しない lint 失敗を発明して誤 block する**。tool の解決は `node_modules/.bin/<tool>` を優先し (npx のネットワーク取得と版ずれを避ける)、解決できなければ whole-tree に落とす。

### 3. commit の file 集合を単一権威にする

`hooks/lib/commit-files.sh` の `commit_files_from_cmd` を lint 関所と lane 関所 (ADR 0017) が共有する。`-a` の扱いのような細部が二箇所で drift すると、片方だけが緩い穴になる (ADR 0005 guard 1 と同じ理由)。

## Consequences (帰結)

- **lane worker が他人の debt で止まらなくなった。** lane を出る動機が消える。ADR 0017 (越境の物理的封鎖) と対になって初めて「塞いだ上に、塞がれても困らない」が成立する。
- **既存の debt がツリーに在っても、それを触らない commit は通る。** これは意図した緩和である: 判定対象は commit であって歴史ではない。ツリー全体の清潔さは CI (whole-tree lint) と lead の main 上の commit が担保する。
- **cross-file な lint 規則 (未使用 export の検出など) は commit 単位では取り逃す。** file 単位で見えない規則は原理的に scope できない。ここは CI の whole-tree lint が backstop。
- `prettier` は拡張子を絞らない (ほぼ何でも整形する) ので、commit が運ぶ file をそのまま渡す。
- **incident の diagnosis は棄却した。** 「メインリポツリーで lint を走らせる」は実装と一致しない。lint hook の cwd は正しい。直すべきは cwd でなく**信号の粒度**だった。incident に訂正を記録した。
