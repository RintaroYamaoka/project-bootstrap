# review — feat_skills-dedup-honesty (sprint 2026-07-10-star5-hardening, lane B)

verdict: reject

- reviewer: read-only adversarial subagent (lead 集約)。日付: 2026-07-10。対象 HEAD 687ad7f
- 検証済みで問題なし: frontmatter description 6 skill とも byte 一致 (auto-fire 不変) / hook 数 20 正確 / scope 逸脱ゼロ / wip_limit・.gate 形式・4 罠・6th seam axis・並列 3 形態は権威箇所に残存 / ポインタ 78 path 実在 (不実在は runtime 生成物のみ) / integrate Step 3 正直化は実装と一致 / plan は gate parser で open=0

## reject の根拠

1. medium — 「Class A (例過適合) と Class B (special-casing) は成果物上同じ表層形になる → 分類せず両方に効く緩和を張る」という診断規範が、verification SKILL の 2 箇所から削除されポインタ化されたが、**ポインタ先 (7th seam 節) にも ADR 0016 にも存在しない = repo から完全消失** (branch tree で `表層形` 0 hit、main は 2 hit)。plan の PASS 行「畳んだ規範の各々に単一権威」をこの項目について偽にする。

## 付随指摘 (non-blocking)

2. low — 「54 参照の機械検査」は名前トークンのみで散文規範を覆わない (上記 1 がその隙間から抜けた)。名前レベルの消失ゼロは独立再検査で確認済み。
3. low — plan evidence の `.bootstrap-` 残存内訳が実態と不一致 (実残存は README:73 / project-bootstrap:172 / sprint-plan frontmatter の 3 箇所)。
4. info — plan skill の正直化注記「裏付けは downstream」がやや過大 (既存 file への Edit は挙げた 2 gate のどちらも捕まえない)。

## 要求修正 (最小、これで approve に転じる)

- 7th seam blockquote (または ADR 0016 — ただし ADR は lane 外なので SKILL 側) に消失規範を復元
- plan evidence 行 2 件を実態に合わせ更新
- (任意) plan skill 注記の裏付け範囲を正確化
