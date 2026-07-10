# review — feat_hook-detector-hardening (sprint 2026-07-10-star5-hardening, lane A)

verdict: approve

- reviewer: read-only adversarial subagent (lead 集約)。日付: 2026-07-10
- 実測裏取り (victim repo に敵対 JSON 実注入 + main との baseline 比較):
  - P0 push 素通り封鎖: `git -C/-c/--git-dir/-P/--no-pager push`・path-prefix・`command git`・`env GIT_DIR=x git`・tab 区切り・subshell/backtick/`$()`・refspec 各形すべて rc=2 (main では rc=0 素通りを確認)。`--all/--mirror/--force-with-lease --all` は for-each-ref 展開で fail-closed。
  - bare stash の compound 素通り封鎖 / commit 系 detector の global-opt・path-prefix 捕捉 / `mygit`・message 内 `push` の over-detect なし。
  - legit flow (`push origin feature`・`-u`・`-o ci.skip`・`--force-with-lease origin feature`) 全て rc=0 = over-block なし。marker 不在は fail-open。
  - 45 suites green。mutation 2 件実注入で kill 確認 (plan 記載の 6 変異の証拠実在)。hooks.json 不変・doctor 台帳 stale 化なし・scope 逸脱ゼロ。

## 指摘

1. minor (doc overclaim・pre-existing) — git-invocation.sh / protected-branch.sh / merge-targets.sh の header が quoted-arg limit を「never silently bypass」と記述するが、quoted git-head/subcommand token や `sh -c "…"` 内は silent under-detect (main と同一の既存穴、本 branch の退行ではない。live bypass 面は厳密に縮小)。→ merge 前に lane A へ文言訂正を差し戻し済み (verdict は approve のまま)。
