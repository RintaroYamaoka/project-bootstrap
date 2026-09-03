# 2026-09-03-cross-claude-wip-false-positive: 終了済み session の記録で commit が止まる誤検知を塞いだ (v0.36.1)

セッション期間: `2026-09-03 午後`
本 doc の目的: **次の Claude が cold restore できる状態**を残す。

---

## 1 行で言うと

`block-cross-claude-wip.sh` が「**過去にそのファイルを編集した**」という transcript の記録だけを根拠に
intruder 判定していたため、**巻き込む WIP が1件も存在しない正当な commit を止めていた**。
判定に self-staged set(当 session が `git add <path>` で名指しした file)を足して塞ぎ、**v0.36.1** としてリリースした。

## どこで踏んだか (実例)

別 repo (`propagate-creative-intelligence`) で feature を commit しようとして発生。

- 止められたのは `db/schema.pg.ts` / `db/schema.ts` / `scripts/etl_sqlite_to_postgres.mjs` の3本
- 実態: **未 staged の変更ゼロ**、staged 差分は **54行の追加のみで全て当 session が書いたもの**
- foreign 判定の出どころは前日 (9/2) の session。その編集は**既に main にマージ済み**で、
  working tree にも index にも残っていなかった
- 加えて、その transcript の **mtime だけが中身の最終記録より 13.7 時間後ろにずれていた**
  (最終行が `cost-state` のメタデータ行)。鮮度窓は mtime で判定するので、終了済み session が
  「稼働中」に見えていた

## 何を直したか

### 1. self-staged set を判定に足した (本丸)

巻き込み事故の本体は「**自分が選んでいない file が index に居る**」こと。したがって
当 session が `git add <path>` で **path を名指しして** index に入れた file は自分のもの。

- bulk staging (`add -A` / `.` / `-u`) は path を名指ししないので self にならず、
  **実事故の経路 (別 terminal の bulk stage → `--amend` で混入) は塞がったまま**
- 読んだだけの path (`cat foo`) も self にしない

### 2. command matcher の境界判定バグ

transcript の command は改行を JSON の `\n` で持つ。`cd repo\ngit add path` のとき
`git` の直前の文字は `n` (英数字) なので、「英数字でない文字が前置」条件で弾いていた。
境界判定をやめ、`git -C <dir> add` のような値つきグローバルオプションも数えるようにした。

### 3. 回帰テスト 5 本

名指し staging は通る / bulk staging は通さない / 読んだだけの path は self にしない /
`\n` 直後の `git add` / `git -C <dir> add`。
**既存 10 assertion (実事故由来の `--amend` 回帰を含む) は不変で green**、suite 全 54 本 green。

## 残課題

| 項目 | 状況 | 対応案 |
|---|---|---|
| **transcript の mtime ずれ** | 中身の最終記録より後ろにずれることがある(Claude Code 側がメタデータを追記するため)。今回は手で揃えたが、再発する | 鮮度窓を mtime でなく **中身の最終 timestamp** で判定すれば根本的。ただし全 sibling を舐めるコストが増えるので、hot path の予算 (ADR 0026) と相談 |
| **「編集が今も未コミットか」を見ていない点は残る** | self-staged で実用上は塞がったが、`git add` を経ずに index へ入った他 session の編集は依然 foreign 扱い(= 本来の意図どおり) | 現状で正しい。過剰に緩めない |

## バックグラウンドプロセス

無し。

## 触ったファイル

- `hooks/block-cross-claude-wip.sh` — self-staged set の追加と matcher 修正
- `tests/hooks/block-cross-claude-wip.test.bash` — 回帰 5 本追加 (10 → 15 assertion)
- `CHANGELOG.md` / `.claude-plugin/plugin.json` — 0.36.1

## 重要な memory / docs references

1. `MAINTENANCE.md` のリリース手順 — CHANGELOG 昇格 → `plugin.json` bump → commit → tag+push。
   **`marketplace.json` は別 repo** (`~/dev/my-projects/claude-plugins`) で `plugins[].version` を同期する
2. 誤検知は「安全側」ではない — 規律を回避する動機を作る (MAINTENANCE.md の gate 追加時の注意と同じ思想)

## 検証手順

```bash
bash tests/hooks/block-cross-claude-wip.test.bash          # 15 assertions, 0 failed
for t in tests/hooks/*.test.bash; do bash "$t" | tail -1; done   # 全 green
```

## 次セッションへの起動文 (= コピペ用)

```
docs/bootstrap/handoffs/2026-09-03-cross-claude-wip-false-positive.md を読んで状況把握してから、
残課題の「transcript の mtime ずれ」を、鮮度窓を中身の最終 timestamp で判定する形に変えるか
判断して。hot path のコスト (ADR 0026) を測ってから決めること。
```
