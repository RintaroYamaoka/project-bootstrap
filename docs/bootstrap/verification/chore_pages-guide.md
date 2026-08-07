# verification plan — chore/pages-guide (完全ガイドの GitHub Pages 公開)
# 意図: プラグイン全体の解説ページ (docs/guide/index.html) を repo に正本化し、GitHub Pages で配信する。
# 跨いだ境界:
#   (a) 配信面 — Pages は repo の外の実体 (build_type=workflow の有効化 + Actions 実走 + CDN 配信)。
#       merge ≠ deployed の env seam そのもの (prod-endpoints incident の教訓)
#   (b) 公開面 — artifact 版は user 個人向けだった。公開ページに user 環境固有の記述
#       (個別 repo 名 / 個人環境の plugin 状態) が混ざると誤情報になる
#   (c) 正本の二重化 — ガイドは README/SKILL/ADR の要約であり、食い違い時の優先順位を明示しないと
#       ガイド自体が将来 drift して誤解を配る
# 落とした範囲: 下記 DROP 2 行
# STATUS | kind | behaviour | oracle | by | evidence/note
PASS | unit     | index.html が完全な HTML 文書 (doctype/html/head/body、self-contained、外部読み込みなし) | html.parser の parse + 構造 grep | ai | parse OK / </html> 1 個 / CDN・外部 URL 参照なし (style/svg inline)
PASS | unit     | 公開ページに user 環境固有の記述が無い | grep (個別 repo 名・退役 plugin の個人環境注意) | ai | kanban-flow / propagate-ai への言及 0 件 (artifact 版から除去・一般化)
PASS | contract | ガイドが正本でないことの明示 (drift 時の優先順位) | ページ末尾の footnote 文言 | ai | 「詳細が食い違ったら正本 (README/SKILL.md/ADR) が勝ちます」を明記
PASS | unit     | pages.yml が valid YAML で、配信対象が docs/guide のみ (ADR 等の md を Pages 面に載せない) | yaml.safe_load + upload-pages-artifact の path | ai | path: docs/guide / trigger paths も docs/guide/** と pages.yml のみ
PASS | e2e      | Pages サイトが repo に有効化されている (build_type=workflow) | GitHub API の実応答 | ai | POST /pages が html_url = rintaroyamaoka.github.io/project-bootstrap/ を返した
PASS | unit     | 既存 hook / gate に影響なし (docs/** は source 面でないため関所対象外) | 既存 self-CI | ai | hooks 無改変。tests/hooks 53 suites は v0.34.0 リリース時点の緑から変更する差分なし (docs+workflow のみ)
DROP | e2e      | 実 URL が 200 で配信され本文が読める | n/a | ai | workflow_dispatch は workflow が default branch に載るまで GitHub API が 404 を返し、merge 前に実測不能。merge の push 自体が paths トリガで deploy を起動するので、**merge 直後に curl で 200 と本文を実査してから「完了」を報告する** (merge ≠ deployed の規律。実査するまで done と言わない)
DROP | unit     | ガイド本文と README/SKILL の内容一致の機械検査 | n/a | ai | 要約と正本の一致は機械検査できない (言い換えの同義性は既約)。footnote の優先順位明示 + 将来の乖離は「読んだ人が正本に当たる」導線で受ける。乖離が実害を出したら incident に記録して更新責務を MAINTENANCE.md に足す、が昇格条件
