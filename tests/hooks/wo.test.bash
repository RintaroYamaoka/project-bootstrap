# Unit tests for hooks/lib/wo.sh — the single authority for parsing a Work Order.
#
# The WO is this subsystem's shared contract: every skill writes it and both gates
# read it. A drifting parser here would silently fail OPEN the completeness gate,
# which is the worst fail-mode this repo recognises. So the parser gets its own
# tests independent of the gates that consume it.

# shellcheck source=helper.bash
. "$(dirname "${BASH_SOURCE[0]}")/helper.bash"
# shellcheck source=../../hooks/lib/wo.sh
. "$(dirname "${BASH_SOURCE[0]}")/../../hooks/lib/wo.sh"

FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT

# --- fixtures ---------------------------------------------------------------

# A fully filled, orderable WO.
cat > "$FIX/good.md" <<'EOF'
---
id: WO-0007
slug: add-export
status: ordered
branch: feat/add-export
retry_limit: 3
budget_tokens: 200000
opened: 2026-08-01
ordered: 2026-08-02
accepted:
escalations: 0
rejections: 1
---

<!-- guidance that must be ignored: <not-a-placeholder> -->

# WO-0007 — CSV エクスポートを足す

## 1. 目的

保存した集計を手元に取り出す口が無い。

## 2. 作業範囲

- `src/export/**`
- `src/api/export.ts`

## 3. 変更禁止範囲

- `src/core/contract.ts` — 外部契約

## 4. 守るべき既存条件

- charter.md の「制約」: レート制限 60 req/min
- ADR 0011

## 5. 優先順位

後方互換 > 実行速度

## 6. 例外時の判断方法

未定義の列が来たら握り潰さず失敗させる。

## 7. 継ぎ目

- `Repository.load(id)` — `src/infra/repository.ts:42`

## 8. 完了条件 (DoD)

- [ ] D1: 100 行の CSV が落ちてくる
- [ ] D2: 空集合でヘッダ行だけ返る

## 9. 検証方法

- D1: `tests/export.test.ts::downloads`
- D2: `HUMAN` — 実機で空アカウントを開く

## 10. 停止条件

- **再試行上限**: frontmatter に従う
- **予算上限**: frontmatter に従う
- **エスカレーション条件**: 契約を変えないと DoD を満たせないと判明したとき

## 11. 決めてよいこと / 決めてはいけないこと

**決めてよいこと**: 列の並び

**決めてはいけないこと**: 契約の形

## 12. 事前レビュー

| # | 観点 | 指摘 | 状態 |
|---|---|---|---|
| 1 | 曖昧さ | 「集計」の範囲が二通り読める | closed |
| 2 | 異常系 | 巨大データ時の挙動が未定義 | deferred:U3 |
EOF

# The shipped template: every fillable slot is still a placeholder.
cp "$(dirname "${BASH_SOURCE[0]}")/../../templates/docs/bootstrap/commission/wo/TEMPLATE.md" "$FIX/template.md"

# --- frontmatter ------------------------------------------------------------

test_case "frontmatter: reads a value"
assert_eq "ordered" "$(wo_frontmatter "$FIX/good.md" status)"
assert_eq "WO-0007" "$(wo_frontmatter "$FIX/good.md" id)"
assert_eq "3" "$(wo_frontmatter "$FIX/good.md" retry_limit)"
assert_eq "1" "$(wo_frontmatter "$FIX/good.md" rejections)"

test_case "frontmatter: empty value reads as empty, not as the next line"
assert_eq "" "$(wo_frontmatter "$FIX/good.md" accepted)"

test_case "frontmatter: unknown key is empty"
assert_eq "" "$(wo_frontmatter "$FIX/good.md" nope)"

test_case "frontmatter: a key-looking line in the BODY is not frontmatter"
# `status:` appears nowhere below, but `id:` style lines could; the reader must stop at the closing ---.
assert_eq "kebab-slug" "$(wo_frontmatter "$FIX/template.md" slug)"

# --- section extraction -----------------------------------------------------

test_case "section body: returns only that section, comments stripped"
body="$(wo_section_body "$FIX/good.md" 5)"
assert_eq "後方互換 > 実行速度" "$(printf '%s' "$body" | tr -d '\n')"

test_case "section body: multi-line section keeps its lines"
assert_eq "2" "$(wo_section_body "$FIX/good.md" 2 | grep -c '^- ')"

# --- filled / unfilled ------------------------------------------------------

test_case "filled: a real WO has no unfilled sections"
assert_eq "" "$(wo_unfilled_sections "$FIX/good.md")"

test_case "filled: the shipped template is unfilled everywhere"
assert_eq "1 2 3 4 5 6 7 8 9 10 11 12" "$(wo_unfilled_sections "$FIX/template.md")"

test_case "filled: a section holding only a placeholder line is unfilled"
sed 's|^後方互換 > 実行速度$|<優先順位>|' "$FIX/good.md" > "$FIX/ph.md"
assert_eq "5" "$(wo_unfilled_sections "$FIX/ph.md")"

test_case "filled: a placeholder wrapped in list marker + backticks is still a placeholder"
sed 's|^- `src/api/export.ts`$||; s|^- `src/export/\*\*`$|- `<src/area/**>`|' "$FIX/good.md" > "$FIX/ph2.md"
assert_eq "2" "$(wo_unfilled_sections "$FIX/ph2.md")"

test_case "filled: angle brackets INSIDE a line are not placeholders (generics survive)"
sed 's|^- `Repository.load(id)` .*$|- `save(id): Promise<void>` — `src/infra/repository.ts:42`|' "$FIX/good.md" > "$FIX/gen.md"
assert_eq "" "$(wo_unfilled_sections "$FIX/gen.md")"

test_case "filled: an entirely missing section counts as unfilled"
grep -v '^## 6\.' "$FIX/good.md" | sed '/未定義の列が来たら/d' > "$FIX/miss.md"
assert_eq "6" "$(wo_unfilled_sections "$FIX/miss.md")"

# --- DoD / oracle identity check -------------------------------------------

test_case "checksum: DoD ids and oracle ids are extracted"
assert_eq "D1 D2" "$(wo_dod_ids "$FIX/good.md")"
assert_eq "D1 D2" "$(wo_oracle_ids "$FIX/good.md")"

test_case "checksum: a DoD row with no oracle is detected"
sed '/^- D2: `HUMAN`/d' "$FIX/good.md" > "$FIX/nooracle.md"
assert_eq "D2" "$(wo_dod_without_oracle "$FIX/nooracle.md")"

test_case "checksum: an oracle for a non-existent DoD is detected"
sed 's|^- \[ \] D2: .*$||' "$FIX/good.md" > "$FIX/extra.md"
assert_eq "D2" "$(wo_oracle_without_dod "$FIX/extra.md")"

test_case "checksum: a matching pair reports nothing"
assert_eq "" "$(wo_dod_without_oracle "$FIX/good.md")"
assert_eq "" "$(wo_oracle_without_dod "$FIX/good.md")"

# --- pre-review -------------------------------------------------------------

test_case "pre-review: counts data rows, ignoring header and separator"
assert_eq "2" "$(wo_prereview_rows "$FIX/good.md")"

test_case "pre-review: closed and deferred rows are resolved"
assert_eq "" "$(wo_prereview_unresolved "$FIX/good.md")"

test_case "pre-review: an open row is reported by its number"
sed 's/| closed |/| open |/' "$FIX/good.md" > "$FIX/open.md"
assert_eq "1" "$(wo_prereview_unresolved "$FIX/open.md")"

test_case "pre-review: an empty state cell is unresolved (blank is not consent)"
sed 's/| 1 | 曖昧さ | 「集計」の範囲が二通り読める | closed |/| 1 | 曖昧さ | x |  |/' "$FIX/good.md" > "$FIX/blank.md"
assert_eq "1" "$(wo_prereview_unresolved "$FIX/blank.md")"

test_case "pre-review: a table with zero data rows reports zero (gate treats it as un-reviewed)"
sed '/^| 1 |/d; /^| 2 |/d' "$FIX/good.md" > "$FIX/norows.md"
assert_eq "0" "$(wo_prereview_rows "$FIX/norows.md")"

# --- unknown (未決) references ---------------------------------------------

test_case "unknowns: ids referenced from section 4 are listed"
sed 's|^- ADR 0011$|- 未決 U7 に依存する|' "$FIX/good.md" > "$FIX/u.md"
assert_eq "U7" "$(wo_referenced_unknowns "$FIX/u.md")"

test_case "unknowns: deferred ids in section 12 are NOT treated as section-4 references"
# U3 appears only in the pre-review table of good.md; it must not surface here.
assert_eq "" "$(wo_referenced_unknowns "$FIX/good.md")"

# --- charter unknown ledger -------------------------------------------------

cat > "$FIX/charter.md" <<'EOF'
## 未決台帳

| ID | 論点 | 状態 |
|---|---|---|
| U1 | まだ | OPEN |
| U2 | 決着 | CLOSED |
| U3 | 空欄 |  |
EOF

test_case "charter: OPEN and blank-state unknowns are open, CLOSED is not"
assert_eq "U1 U3" "$(charter_open_unknowns "$FIX/charter.md")"

test_case "charter: a missing file yields nothing (unadopted project is not blocked)"
assert_eq "" "$(charter_open_unknowns "$FIX/nope.md")"

test_case "charter: every ledger id is listed regardless of state"
assert_eq "U1 U2 U3" "$(charter_unknown_ids "$FIX/charter.md")"

test_case "charter: a missing file has no ids (the gate turns that into its own problem)"
assert_eq "" "$(charter_unknown_ids "$FIX/nope.md")"

# --- deferred ids -------------------------------------------------------------
# wo_prereview_unresolved only judges the SHAPE of the state cell, so `deferred:U99`
# reads as resolved. The id itself has to be cross-checked against the ledger or the
# forbidden move (defer without naming the gap) passes.

test_case "pre-review: deferred ids are extracted from the state cells"
assert_eq "U3" "$(wo_prereview_deferred_ids "$FIX/good.md")"

test_case "pre-review: a closed row defers to nothing"
sed 's/| deferred:U3 |/| closed |/' "$FIX/good.md" > "$FIX/nodefer.md"
assert_eq "" "$(wo_prereview_deferred_ids "$FIX/nodefer.md")"

# --- scope --------------------------------------------------------------------

test_case "scope: globs are extracted without list markers or backticks"
assert_eq "src/export/** src/api/export.ts" "$(wo_scope_globs "$FIX/good.md" | tr '\n' ' ' | sed 's/ $//')"

test_case "scope: covers a path inside a declared glob"
wo_covers_path "$FIX/good.md" "src/export/csv.ts" && r=0 || r=1
assert_eq "0" "$r"

test_case "scope: covers an exact declared path"
wo_covers_path "$FIX/good.md" "src/api/export.ts" && r=0 || r=1
assert_eq "0" "$r"

test_case "scope: does not cover a path outside every glob"
wo_covers_path "$FIX/good.md" "src/core/contract.ts" && r=0 || r=1
assert_eq "1" "$r"

finish
