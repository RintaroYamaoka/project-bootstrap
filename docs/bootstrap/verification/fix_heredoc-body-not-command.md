# verification plan — fix/heredoc-body-not-command (ADR 0025, v0.35.0)
# 意図: heredoc 本文は「実行されるコマンド」ではなく stdin に渡されるデータなので、gate の
#   判定対象から外す。ただし本文が実際に実行される形 (シェル/eval に食わせる) は外さない。
# 跨いだ境界:
#   (a) 全 Bash gate が通る単一入口 (parse_command) の契約変更 — 16 消費者に一斉に効く回帰面。
#       誤ると「巻き込み add / 破壊系 git を通す」= 最も重い無音の fail-open
#   (b) 検出を**緩める**向きの修正 — 誤検知を消しつつ、実検出を落としていないかが本質
#   (c) 引数の値を必要とする消費者 (lib/commit-files.sh 等) — quote を剥がさない判断の妥当性
#   (d) テスト自身の検出力 — 「壊しても同じ出力になる経路」は緑のまま穴を通す (6 番目の seam)
# 落とした範囲: 下記 DROP 3 行
# STATUS | kind | behaviour | oracle | by | evidence/note
PASS | unit        | heredoc 本文が落ちる: quoted label / `<<-` タブ終端 / 未終端 / 1 行 2 本 / herestring は非対象 / heredoc 無しは素通し | 期待値 (strip_heredoc_bodies の出力) | ai | tests/hooks/parse-command.test.bash 31 assert (11 追加)
PASS | unit        | **検出を落としていない**: 終端の後ろの実コマンドが残る / `<<-` 終端後の実コマンドが残る / 裸の実行形は不変 | 期待値 | ai | 同上。とくに「終端後を飲み込まない」は fail-open 方向の回帰面なので専用 assert
PASS | unit        | fail-closed 例外: `bash <<EOF` / `/bin/sh <<EOF` は本文を残す (本文が実行されるため) | 期待値 | ai | 同上 2 assert
PASS | unit        | parse_command の契約: 本文を落として返す / unparseable は非ゼロのまま (fail-closed 不変) | 期待値 + 終了コード | ai | 同上 2 assert
PASS | e2e         | 実 hook で誤検知が消え、実検出は残る (walker 経路 = block-add-all、raw regex 経路 = block-dangerous-git-ops の両方) | 実 hook の exit code (9 ケース × 2 hook) | ai | 修正前: heredoc 4 形が誤 block → 修正後: pass。実行形 (裸 / 終端後 / `bash <<EOF`) は block のまま。dangerous-git-ops の heredoc 内 `reset --hard` も pass に
PASS | metamorphic | assert が実装を握っているか — 実装の中核を壊してテストが赤くなるか | 注入した変異をテストが殺すか | ai | 5 変異。①シェル例外削除 / ④終端一致を常に真 / ⑤演算子行の出力削除 = kill。③`<<-` タブ除去削除 = **初回生存 → 本物のテストギャップ**(終端後にコマンドが無く出力が同じになる。差は「実コマンドを飲み込む」= fail-open 向き) → 差が出る入力を追加して kill。②herestring ガード = **等価変異** (ラベル走査が既に `<` を弾く) と判明、コードに明記して残置
PASS | unit        | 回帰面: 既存 53 suite が無改変で緑 (16 消費者すべてが parse_command 経由) | 全 suite の実走 | ai | 53/53 pass、bash -n OK
PASS | contract    | 既知の残余を無音にしない: quoted 引数の over-detect が残ることを lib ヘッダ・ADR 0025・CHANGELOG に明記 | grep による記載確認 | ai | 3 箇所に記載。回避策 (heredoc / `-F <file>`) が本版から通ることも併記
DROP | unit        | quoted 引数の over-detect 自体の修正 | n/a | ai | quote 剥がしは引数の**値**を消し、pathspec を引数から取る消費者 (commit-files.sh) が空白入り path を無音で取りこぼす = lint/test/retired gate の fail-open。誤検知より重いので本 PR では扱わない (ADR 0025 の代替案節に理由を記録)。直すなら parse_command でなく検出側で、消費者を壊さないことが条件
DROP | e2e         | 発見元 (ai-reception) で実際に踏んだ commit が通ることの実査 | n/a | ai | 別 repo の作業ツリー状態に依存し、この PR の merge 前には再現環境を固定できない。**リリース後に発見元で最小再現を実行して確認する** (incident の最小再現がそのまま手順)
DROP | unit        | `cat <<$VAR` のような変数展開された heredoc ラベル | n/a | ai | 完全なシェルパーサが要る。ADR 0019 が既に「quote/escape された git-head」で同種の限界を宣言済みで、同じ性質の残余。実害が出たら incident 化する、が昇格条件
