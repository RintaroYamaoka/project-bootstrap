# 0025 — heredoc 本文は「実行されるコマンド」ではない (判定対象から外す)

- **Status**: Accepted
- **Date**: 2026-08-08
- **Deciders**: Rintaro Yamaoka
- **References**: ai-reception の incident `docs/bootstrap/incidents/2026-08-08-block-add-all-heredoc-false-positive/` (発見元・最小再現つき) / ADR 0019 (git 呼び出し検出の単一権威) / ADR 0018 (gate の信号は「この commit が運ぶもの」) / `skills/project-bootstrap` 原則② (信号選び) / 退役 `kanban-flow` の `bash-guard.mjs` (同型の配慮を持っていた先例)

---

## Context (背景)

ai-reception を kanban-flow から bootstrap へ全面移行する作業 (#477) の最中に、
**gate が規律の説明そのものを block する**誤検知が見つかった。

```
git commit -F - <<'MSG'
chore: 規約を書く

一括 stage は `git add -A` を使わない
MSG
```

commit メッセージ本文に禁止コマンドの字面が含まれているだけで
`block-add-all.sh` が exit 2 する。`cat <<'EOF' … EOF` のように **git と無関係な
コマンドでも起きる**。

### 原因

gate は「コマンド文字列」を走査するが、**heredoc 本文は実行されるコマンドではなく
stdin に渡されるデータ**である。この区別が実装に無かった:

- **token walker 経路** (`lib/git-invocation.sh`、11 hook が使用): 改行を単なる空白として
  word-split するため、本文のトークンがコマンド列に流れ込み `git` → `add` → `-A` と読まれる
- **raw regex 経路** (`block-dangerous-git-ops.sh`): `git[[:space:]]+reset.*--hard` を
  コマンド全体に当てるため、本文の字面をそのまま拾う

実測した誤検知の範囲 (修正前):

| 形 | block-add-all | dangerous-git-ops |
|---|---|---|
| `cat <<'EOF'` 本文に禁止語 | 誤検知 | 誤検知 |
| `git commit -F -` の heredoc メッセージ | 誤検知 | 誤検知 |
| `<<-` 形式 / 未終端 heredoc | 誤検知 | 誤検知 |
| quoted 引数 `-m "… git add -A …"` | 誤検知 | — |

### なぜ「安全側の誤検知」で済まないか

fail-mode としては安全側 (通すべきものを止める) に見える。しかし本件が止めていたのは
**この規律そのものを文章で説明する行為**である。CLAUDE.md・PR 本文・commit メッセージ・
incident 記録・hook のドキュメント — 禁止コマンドの字面を書く機会は、規律を運用している
repo ほど多い。発見時に実際に `/permissions` で hook を deny にする案が出た。

これは本プラグインが繰り返し警告してきた **「gate が自分の bypass を作る」** 失敗モードの
実例であり、原則②「gate は proxy でなく**行為そのもの**を信号にする」の違反でもある
(**テキストの字面**という proxy を行為と誤読していた)。「塞ぐ」と「塞がれても困らなく
する」は対で設計する、が本プラグインの立場である。

## Decision (決定)

**`parse_command` が heredoc 本文と終端ラベル行を落としてから返す。**
演算子行 (= 実際のコマンド) と本文の外にある行は保持する。

置き場所は `lib/parse-command.sh` (= 全 gate が通る単一の入口)。理由:

- 誤検知は **token walker 経路と raw regex 経路の両方**に在り、walker だけ直しても片肺になる
- 16 の消費者すべてが `parse_command` を通るので、ここが唯一の単一点である
- heredoc 本文を必要とする消費者は 1 つも無い (pathspec も flag も演算子行に在る)

### fail-direction — 本文が実行される形は落とさない

本文を落とすのは検出を**緩める**向きなので、無条件には適用しない。
**`bash <<EOF … EOF` のようにシェル/eval に食わせる heredoc は、本文がコマンドとして
実行される**ので、その行の heredoc は本文ごと gate の視界に残す (fail-closed を維持)。
判定は演算子行のトークンに `sh|bash|zsh|dash|ksh|eval|source|.` (path 付きを含む) が
在るか。未終端 heredoc は「そこから末尾まで全部が本文」として扱う (シェルもそう解釈する)。

### 採用しなかった代替案

- **各 hook で個別に heredoc を除く** — ADR 0019 が潰した「各 gate が自前の判定を持つ」
  形への逆戻り。新しい gate が追加されるたびに穴が復活する
- **quoted 文字列も一緒に剥がす** (退役 `kanban-flow` の `bash-guard.mjs` がやっていた形) —
  **採らない**。quote を剥がすと引数の**値**が消え、pathspec を引数から取る消費者
  (`lib/commit-files.sh` 等) が「空白を含む path」を無音で取りこぼす。lint / test / retired の
  各 gate が「この commit が運ぶ file」を誤るのは、誤検知より重い**無音の fail-open**である。
  よって quoted 引数の over-detect は**既知の残余として明示的に残す** (下記)
- **gate を止める / marker を外す** — 発見時に頭をよぎった選択肢だが、これは誤検知が
  規律を殺す経路そのもの。記録として残す

## Consequences (結果)

### 良い影響

- 規律を**文章で説明する行為**が gate に妨げられなくなる (このプラグイン自身の
  README・ADR・incident を書く作業を含む)
- 修正は 1 か所で、walker 経路 (11 hook) と raw regex 経路の両方が同時に直る
- `bash <<EOF` の検出は維持されるので、実行される本文への射程は狭まっていない

### 悪い影響 / トレードオフ

- **`parse_command` の契約が「生の command 文字列」から「実行されるコマンド文字列」へ
  変わった**。生文字列が要る将来の消費者は `parse_json_string_field command` を直接呼ぶ必要がある
- **quoted 引数の over-detect は残る** (`git commit -m "… git add -A …"` は今も block される)。
  回避策は heredoc かファイル経由 (`-F <file>`) で、どちらも本 ADR 後は通る。
  無音にしないため `lib/parse-command.sh` のヘッダと本 ADR に明記した
- heredoc 解析は完全なシェルパーサではない。ラベルの quote/backslash 形と `<<-` は扱うが、
  行内で変数展開された演算子 (`cat <<$VAR`) までは追えない (ADR 0019 の既知の限界と同じ性質)

### 移行後に必要な保守

- 新しい Bash gate を足すときは、**必ず `parse_command` を入口にする** (直接 stdin を
  読んで正規表現を当てると、この修正の射程外に落ちる)
- quoted 引数の over-detect を将来直すなら、`parse_command` ではなく**検出側**で行う。
  値を必要とする消費者 (`commit-files.sh`) を壊さないことが条件
