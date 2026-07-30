# 2026-06-11-velocity-fixrev-japanese-blind: velocity の fixrev が日本語 commit を数えられず defect 率が 4 倍過小だった

gate-broad-glob incident の検証中、user の「実データは計測出来ていたの?」への回答として velocity.sh を実 repo で初めて回したことで発見。**Stage 2 trust ladder の安全網 (= レビューを薄くしても壊れていないかを判定する唯一の客観データ) が、肝心の消費先 repo で過小計測になっていた**。

## 関係する file / 識別子

- `scripts/velocity.sh` (旧 :51) — fixrev 判定が `^(fix|hotfix|revert)` (英語 prefix のみ)
- 実測 (2026-06-11、creative-team-app + bootstrap の 4 週合算): 旧判定 fixrev=5 / defect=**3%** → 日本語対応後 fixrev=20 / defect=**12%**
- creative-team-app の直近 4 週 133 非 merge commit 中、旧判定が数えたのは英語 subject の 2 件のみ。「〜を修正」「不具合報告4件を修正」「404修正」等は全て不可視だった

## 1. ミスの一覧

### 1.1 計測 pattern を計測対象の実データで検証しなかった

- **何をした**: 0.15.0 で velocity.sh を書いたとき、fixrev の判定を conventional commits 風の英語 prefix に置き、この repo と消費先の実 commit subject (大半が日本語、fix は「〜を修正」と文中に現れる) に対して照合しなかった
- **何が問題だった**: これは SKILL.md が罠 2 (「actual capability を表記で推測する」) / 罠 4 (「pattern の cohort 副作用を測らない」) として明文化している AI の癖そのもの。計測 script は「動く」だけでは足りず、**pattern semantics が実 cohort と一致するか**が verification の本体だった
- **観測された結果**: defect 率 3% (見かけ上「基準線 11% を大幅に下回る健全」) が報告されうる状態。実態は 12% で、trust ladder の昇降判定 (lane を増やすか / レビューを厚く戻すか) を**逆方向に誤らせる**数字だった

## 2. 真因

> **計測 gate / script の信号も、防御 gate と同じく「判定対象そのもの」で検証しなければならない。** fixrev の判定対象は「defect を直した commit」であり、英語 prefix はその代理 (proxy) にすぎない。代理信号は語彙の分布が変わると無音でズレる — 防御 gate の語彙 regex が言い回しで素通った 2026-05-31 incident と同型の穴が、計測側に残っていた。

## 3. 構造的再発防止

- [x] **fixrev 判定に日本語 defect 語を追加**: `修正` / `バグ` / `不具合` / `誤り` (subject 中のどこでも)。token は実 cohort (creative-team-app 4 週分の全 subject) で精度検証してから採用 (罠 4 の手順を踏む)
- [x] **不採用 token を理由付きで記録**: 「戻す」(= CDへ戻す / 差し戻す という業務フロー語で false positive)、「直し」(= 「やり直し」という incident 記録語に誤反応)、「解消」(= handoff 更新などの非 defect に混入)。除外判断もテストに pin (`tests/hooks/velocity.test.bash` 7)
- [x] **修正後の read-back**: 同一 repo 群で再計測し defect 3% → 12% を確認。新たに数えた commit 一覧を目視サンプル確認し false positive なし
- [x] **基準線の引き直し**: 「基準線 11%」自体が旧方式の数字で比較不能だった (同窓を新方式で再計測すると bootstrap 単体 20%)。新基準線の起点 = 横断 4w 実測 **12%** (velocity.sh header に明記)。旧 11% への言及 (freeze handoff / CHANGELOG 0.15.0) は歴史記録としてそのまま、正本はここと velocity.sh

## 4. 関連 memory / docs

- `docs/incidents/2026-05-31-sprint-advisory-silent/` — 「語彙 regex は proxy で穴が空く」の防御 gate 版
- `skills/project-bootstrap/SKILL.md` 罠 2 / 罠 4 — 本件はその計測 script 版の実例
- memory `user_multi_project` — 計測は横断集計、かつ **user の repo の commit 語彙は日本語** が前提条件に加わる
