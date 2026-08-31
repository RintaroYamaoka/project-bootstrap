# 0026 — PreToolUse gate 群を単一プロセス dispatcher で実行する (Windows 高速化)

- date: 2026-08-31
- status: accepted

## Context

hooks.json は PreToolUse の gate を 1 本 = 1 command で結線していた: Bash tool call ごとに
16 個、Edit|Write|MultiEdit ごとに 6 個の `bash <gate>.sh` プロセスが起動し、各 script は
さらに共通の preamble (`INPUT=$(cat)` / `$(dirname "$0")` / `printf | parse_command` /
`parse_json_string_field` 内の `$(cat)`) で **早期 exit に到達する前に ~7 fork** を払っていた。
12 gate は加えて walker の sed+grep 5 fork を「`ls` にすら」払っていた (2026-08-31 実測調査)。

Linux では 1 Bash call 合計 ~76ms で気づかない。だが **Windows (Git Bash / MSYS) は fork が
エミュレーションで 10-30 倍遅く、1 tool call あたり数秒**になる。user 報告「windows環境で
非常に遅い」の正体はこれ。速度税が重い gate は deny される動機を作る — 誤検知が規律を殺すのと
同型で、**遅さも規律を殺す** (memory feedback_false_positive_kills_the_discipline の速度版)。
この repo は Git Bash を一級ターゲットに設計してきた (bash 3.2-safe / jq-free / .gitattributes
LF 強制 / tr による path 正規化) が、プロセス数そのものは未対策だった。

## Decision

1. **配線は matcher あたり 1 command**: `dispatch.sh edit` / `dispatch.sh bash`。dispatch は
   stdin を builtin `read` で 1 回読み、payload を 1 回だけ parse し、各 gate file を source
   して `gate_*` 関数を旧 hooks.json の結線順に同一プロセスで呼ぶ。最初に block した gate の
   rc 2 と stderr がそのまま dispatcher の出力。未知の mode 引数は fail-closed
   (配線 typo で 22 gate が無音に死なない)。
2. **gate script は「関数 + 単体起動 footer」の二面構成** (`lib/standalone.sh` が入口の単一
   権威)。tests (28 file) と vendoring 消費者の `bash <gate>.sh` 単体起動は不変。gate 関数の
   契約: globals `INPUT`/`CMD`/`FILE` を読む / scratch は `local` / return 0=pass, 2=block。
3. **hot path を fork ゼロに**:
   - `lib/parse-command.sh` に変数 API (`json_field_var` / `parse_command_var` /
     `edit_file_var` / `norm_path_var`) を追加。stdin 版は thin wrapper (単一権威は変数版)。
   - `lib/git-invocation.sh` の walker: sed padding → 純 bash `${var//}` (sentinel \x01/\x02、
     command 自身が制御文字を含む稀ケースのみ sed に fallback)、`| grep -q ''` → カウンタ。
     純 builtin の `*git*` 事前ガードを追加 — walker が検出できる git 起動は必ず部分文字列
     `git` を含むので検出集合は不変 (quoted git-head の under-detect は従来からの既知残余)。
   - `lib/action-gate.sh` のトークナイザも同様に純 bash 化。
   - `tr '\\' '/' | tr -s '/'` の Windows path 正規化 (~10 箇所) → `norm_path_var`。
   - `git rev-parse --show-toplevel` はプロセス内 memo (`lib/repo-top.sh`) で 1 call 1 回。
   - 全 lib に include guard (1 プロセスに 22 gate が同じ lib を source するため)。
4. **cwd / trap を汚す gate は封じ込める**: `block-commit-if-tests-fail.sh` の cd は subshell、
   `block-commit-if-wo-incomplete.sh` の EXIT trap は明示 rm に置換 (dispatcher の trap を
   奪わない)。
5. 実測オラクルは `scripts/bench-hooks.sh` (旧配線 vs dispatch を同一 payload で N 回)。
   Linux (WSL2): Bash call 76ms → 24ms、Edit 38ms → 19ms。Windows 実測は user の Git Bash で
   同 script を回す (verification plan の HUMAN 行)。

## Consequences

- **plugin 経由の消費者は自動で高速化** (hooks.json はプラグインと一緒に配布される)。
  vendoring 消費者は従来配線のまま動く (遅いが正しい)。dispatch.sh + lib/ を vendor して
  2 エントリに配線し直せば同速になる。
- **同期が要る対が 1 つ増えた**: gate を足す/消すときは hooks/README.md の発火順・
  `scripts/doctor.sh` REQ に加えて **`dispatch.sh` の `BASH_GATES`/`EDIT_GATES`** も直す
  (MAINTENANCE.md 更新済み)。dispatch への足し忘れ = plugin 経由で発火しない。
  net: `tests/hooks/dispatch.test.bash` が代表 payload の block/pass parity を固定する。
- **複数 gate が同時に block する入力では最初の 1 本の banner だけ出る** (旧配線は並列に
  全 banner が出えた)。1 つずつ直す UX になるが、block の判定集合そのものは不変。
- gate 関数は 1 プロセスを共有するので **scratch 変数の local 漏れが gate 間汚染になりうる**
  (旧配線には無かった failure class)。変換時に全 gate へ local 宣言を入れ、dispatch.test.bash
  の複合 command ケース (先行 gate の full walk 後に後続 gate が正しく block) で監視する。
- 発火順そのものは旧 hooks.json の順を保存 (injector = stdout JSON を出す唯一の gate が末尾)。
