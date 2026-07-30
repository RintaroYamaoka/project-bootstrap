# 2026-05-25-hook-command-parse-fail-open: security gate が JSON 解析失敗で素通ししていた

7 つの PreToolUse hook が、Bash tool の入力 JSON から `command` 値を
`grep -oE '"command"[^,}]*'` で抜いていた。`[^,}]*` は最初の `,` / `}` で停止するため、
`git commit -m "fix, bug" && git add -A` のような入力で文字列が `git commit -m "fix` に
切れ、後続の危険 op が解析対象から消えて gate が **block すべきものを素通し (fail-open)** した。
SKILL.md が「最も危険」と名指しする silent failure を、それを防ぐはずの gate 自身が踏んでいた。

## 関係する file / 識別子

- `hooks/block-add-all.sh` 他 6 (`block-arch-violations` / `block-commit-if-lint-fails` / `block-commit-if-tests-fail` / `block-cross-claude-wip` / `block-dangerous-git-ops` / `block-push-to-protected`) — 同一の脆弱な抽出行をコピペ共有
- `hooks/lib/parse-command.sh` — 今回新設した共通 parser (fix)
- `tests/hooks/block-add-all.test.bash:18-24` — `input_json` ヘルパーが「コンマ/`}` を避ける」とコメントし、**テストがバグを回避する形で書かれていた** (= バグの自認)

---

## 1. ミスの一覧

### 1.1 危険側に倒れる解析 (fail-open)

- **何をした**: 7 hook で `grep -oE '"command"[^,}]*'` により command を抽出
- **何が問題だった**: `[^,}]*` がコンマ/閉じ波括弧で停止 → コマンド後半が消失。`git commit -m "fix, bug" && git add -A` は `git commit -m "fix` に切れ、`git add -A` が解析から落ちて block-add-all が exit 0 (素通し)。検出失敗が **安全側 (block) でなく危険側 (pass) に倒れていた**
- **観測された結果**: 修正前の repro で `block-add-all` exit = 0 (本来 2)。fix 後 exit = 2

### 1.2 同一バグの 7 ファイルへのコピペ拡散

- **何をした**: 同じ抽出ロジックを各 hook に個別コピー
- **何が問題だった**: 1 箇所の欠陥が 7 箇所に複製され、修正も検証も分散。1 つ直しても他が残る構造
- **観測**: 7 ファイルすべてに literal 同一の 1 行が存在 (grep で確認)

### 1.3 テストがバグを回避する形で書かれていた

- **何をした**: `block-add-all.test.bash` の `input_json` ヘルパーに「コンマ/`}` を含む command は truncate されるので避ける」とコメントを書いて運用
- **何が問題だった**: テストが**バグの存在を認識した上で、それを踏まない入力だけ**を流していた。characterization test が「現状維持」に最適化され、バグを仕様として固定していた
- **観測**: `tests/hooks/block-add-all.test.bash:18-24` のコメント

## 2. 真因

> セキュリティ gate を「正規表現で済む簡単な文字列抜き出し」と誤認し、**解析失敗時にどちらへ倒れるか (fail-open/closed) を設計しなかった**。gate は「検出できなければ通す」が default になっており、これは「検出できなければ止める」であるべきだった。加えて共通処理を関数化せずコピペしたため欠陥が増幅し、テストはバグを回避することで欠陥を隠蔽した。

## 3. 構造的再発防止

- [x] **解析を `hooks/lib/parse-command.sh` に集約**: 末尾の未エスケープ `"` まで読み、`\" \\ \n \t` 等を 1 段デコード。7 hook が source して共用 (コピペ欠陥の構造的排除)
- [x] **fail-closed 化**: 解析不能時は各 hook が `exit 2` で block。gate の default を「止める側」に反転
- [x] **self-CI (`.github/workflows/test.yml`)**: push/PR で全 hook テストを ubuntu で実行。fail-open regression を server 側 gate で二度とマージさせない
- [x] **regression テスト**: `parse-command.test.bash` + 各 hook に「コンマ/エスケープ入りで危険 op が block される」ケース。バグを回避せず**バグを踏む入力**を仕様として固定
- [x] **memory `feedback_fail_closed_security_gates.md` に昇格**: 「検出系 gate は解析/検出失敗時に必ず安全側 (block) に倒す」を default ルール化

## 4. 関連 memory / docs

- [`feedback_fail_closed_security_gates.md`](../../../../memory/feedback_fail_closed_security_gates.md) — 検出 gate は失敗時に block 側へ倒す
- 関連: `skills/project-bootstrap/SKILL.md` の「silent failure / 危険側に倒れる静かな失敗」節 — 本件はその警告を gate 自身が踏んだ実例
- 関連 incident: [`2026-05-24-shared-index-amend-mixing`](../2026-05-24-shared-index-amend-mixing/README.md) — 同じく hook で防ぐべき事故の系譜
