# 2026-09-03: require-test-companion が「実行できない test」を要求していた

セッション期間: `2026-09-03 夕`
本 doc の目的: **次の Claude が cold restore できる状態**を残す。

---

## 1 行で言うと

`require-test-companion.sh` は companion 候補を source の拡張子から機械的に作っていたため、
**`.tsx` には `.test.tsx` しか認めず、しかし Node の test runner は `.tsx` を実行できない**
(Node 24 は JSX 非対応)。**gate を満たせる唯一のファイルが「一度も実行されない飾り」**という
状態だった。JS/TS 8 拡張子を1つの族として扱うよう直し、**v0.36.2 としてリリース**。

## なぜ「安全側の誤検知」ではないか

0.35.0 の heredoc 誤検知と同型で、しかも一段悪い。あれは**規律を説明する行為**を止めたが、
今回は **gate が decoy を要求していた**。利用者が取れる手は3つしかない:

1. 実行されない `.tsx` を置く → **gate は緑、テストは存在しない**(verification skill が
   7 番目の seam として名指しする「可視オラクルを騙す」形を、gate 自身が誘導していた)
2. hook を `/permissions` で deny → 「gate が自分の bypass を作る」の実例
3. Edit ツールを避けて Bash で書く → gate が無音で素通しになる経路を常用させる

どれも規律を弱める。**発見時、実際に 3 を選ばざるを得なかった**
(propagate-creative-intelligence の `app/page.tsx` 修正、user 判断)。

## 影響範囲は `.tsx` に留まらなかった

`.ts` 実装 + `tests/<name>.test.mjs` companion (= `node --test` では普通の構成) も
同じ理由で誤 block していた。**実測した1リポジトリだけで本物の companion を持つ 10 ファイル**
(`lib/*.ts` 9 本 + `app/page.tsx`) が止められていた。

## 直し方

- JS/TS の 8 拡張子 (`ts tsx js jsx mjs cjs mts cts`) を**互いに読み込める1つの族**として扱い、
  族内なら companion と認める。beside / `__tests__/` / `tests/` / 深い `tests/unit/<layer>/` の
  再帰 fallback すべてで族を跨ぐ
- 探索順は **source 自身の拡張子が先頭**。最頻ケースの当たり位置は変わらない
- **widening は言語境界で止めた** — `.ts` 実装は同名の `.py` test では通らないし逆も通らない
  (回帰テストで両方向を固定)
- block 時の案内は 88 行に展開せず `tests/foo.test.{ts,tsx,js,jsx,mjs,cjs,mts,cts}` の
  brace 形で 11 行のまま保つ
- 新規 fork ゼロ (ADR 0026)。実測 33 → 35 ms/call で bash 起動が支配的、有意差なし

## 残課題

| 項目 | 状況 | 対応案 |
|---|---|---|
| `mts` / `cts` は companion として認めるが**実装拡張子としては素通し** | 実装拡張子の判定リストは `ts\|tsx\|js\|jsx\|mjs\|cjs\|py\|...` のままで `mts`/`cts` を含まない。つまり `foo.mts` を編集しても test は要求されない | 締める向きの変更なので patch では入れない。次の minor で実装拡張子に足すか判断する |
| 配布インデックスの同期 | `claude-plugins` repo 側の `plugins[].version` を 0.36.2 へ | 本 session で対応済みなら不要。未対応なら別 repo で 1 commit |

## バックグラウンドプロセス

無し。

## 触ったファイル

### 永続化したい(すべて PR 経由で main)

- `hooks/require-test-companion.sh` — 族の導入・find fallback の族対応・案内文面
- `tests/hooks/require-test-companion.test.bash` — 回帰 9 assertion 追加 (13 → 22)
- `CHANGELOG.md` / `.claude-plugin/plugin.json` — 0.36.2

### untracked / ephemeral

無し。

## 重要な memory / docs references

1. `MAINTENANCE.md` — リリース手順と「同期が要る対」
2. `docs/bootstrap/handoffs/2026-09-03-cross-claude-wip-false-positive.md` — 直前の同種修正 (0.36.1)
3. ADR 0026 — hot path に fork を置かない制約

## 検証手順

```bash
bash tests/hooks/require-test-companion.test.bash   # 22 assertions, 0 failed
bash tests/hooks/run.sh                             # SUITES: 54 run, 0 failed
```

実リポジトリでの外形確認 (companion 実在の4ファイルが通り、無いものは止まること):

```bash
printf '{"tool_name":"Edit","tool_input":{"file_path":"<repo>/app/page.tsx"},"cwd":"<repo>"}' \
  | bash hooks/require-test-companion.sh; echo $?   # 0 (companion は tests/page.test.ts)
```

## 次セッションへの起動文 (= コピペ用)

```
docs/bootstrap/handoffs/2026-09-03-test-companion-extension-family.md を読んで状況把握してから、
残課題の「mts/cts を実装拡張子に足すか」を次の minor で判断して。
```
