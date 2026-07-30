verdict: approve

# Adversarial integration review — lane P0 (feat/P0-protected-branch-tokenizer)

Reviewer: adversarial integration reviewer (read-only), integrate skill Step 2.
Commit reviewed: ca0ae2f "Fix two live push-gate bugs via single-authority lib/protected-branch.sh"
Worktree: /home/rintaroyamaoka/dev/my-projects/wt-P0-protected

## Scope of change (in-lane, clean)
Exactly the 3 lane-scope files changed (matches .bootstrap-lane):
- hooks/lib/protected-branch.sh (new, 116 lines)
- hooks/block-push-to-protected.sh (re-pointed to the lib)
- tests/hooks/protected-branch.test.bash (new, 31 assertions)
No out-of-lane edits. board.json untouched. The only repo-wide grep hit for similar
sed/push idiom is hooks/block-add-all.sh (`git stash push` — unrelated hook, not coupled).

## Bug class actually closed (the P0 mandate)
Both LIVE bugs in the old gate are an action/topology trace now, not a string proxy:
1. Path-prefixed git was invisible (old detector had no `/` allowance). FIXED:
   cmd_has_git_push allows `/` before `git`, so `/usr/bin/git push` and `./git push`
   are seen; `mygit`/`legit`/`git-push`/`xgit` are correctly NOT matched.
2. Greedy `sed 's/^.*git push//'` inspected only the LAST push of a compound command
   and one segment. FIXED: push_destination_branches walks EVERY segment (&&, ||, ;,
   |, &), resetting in_push on each separator, modeled byte-for-byte on the proven
   lib/merge-targets.sh walker (same set -f noglob word-split, separator padding,
   reset-on-separator).
This is a real tokenized-action trace, not a new string proxy. No new hole introduced.

## Findings
- No blockers.
- No major issues.
- Minor (non-blocking, accepted): the documented known-limit inherited from
  merge-targets.sh — a separator metachar INSIDE a quoted arg (e.g.
  `git push -o "a && b" origin main`) can mis-split without a full shell parser
  (fail-OPEN for that narrow case only). Documented in the lib header exactly as
  merge-targets.sh does; commit-time arch/test gates + CI remain as nets. Acceptable
  and consistent with the established repo pattern.
- Minor (observation, not a defect): the block REASON message text changed from
  `refspec '$tok' → protected branch '$dst'` to `refspec destination → protected
  branch '$dst'`. Cosmetic only; exit codes, fail-closed contract, and the
  implicit-current-branch path are byte-for-byte preserved.

## Sample adversarial traces (all confirmed)
push_destination_branches (unit):
- `git push a && git push origin main`            -> main            (compound, protected push CAUGHT — the core regression)
- `git push origin main && git push origin dev`   -> main,dev        (FIRST push's protected main found, not just last)
- `/usr/bin/git push origin main`                 -> main            (path-prefix)
- `git push origin topic:refs/heads/main`         -> main            (src:dst + refs/heads/ normalized)
- `git push origin +main`                         -> main            (force + stripped)
- `git push origin :main`                         -> main            (delete refspec)
- `git push origin --delete main`                 -> main            (delete via flag)
- `git push --receive-pack push origin main`      -> main            (value flag whose value is literally `push` is skipped, not re-armed)
- `git push -o git origin feat/x ; git push origin main` -> feat/x,main (value=`git` does not re-arm a push across the separator)
- `git push origin main && echo feat/x`           -> main            (NO false-block: echoed branch after && not read)
- `git status`, `foo push origin main`, `xgit push origin main`, `push origin main` -> (empty)  (no false positives)
is_protected (false-block probe — glob is one-directional, on the FILE side):
- branch `mai?` vs pattern `main`  -> no match   (branch side is literal subject; no spurious match)
- branch `m*`   vs pattern `main`  -> no match
- branch `release/x` vs `release/*` -> match      (intended glob)

End-to-end against the LIVE hook (sandbox repo with .bootstrap-protected = main, release/*),
driven via tool_input.command JSON (confirms parse_command JSON-path contract intact):
- BLOCK (exit 2): `git push origin main`, `/usr/bin/git push origin main`,
  `./git push origin main`, `git push origin feat/x && git push origin main`,
  `;`-joined variant, `HEAD:main`, `+main`, `topic:refs/heads/main`, `release/1.0`,
  implicit `git push` while ON protected main, and `--repo X origin +HEAD:refs/heads/main`
  (value-flag does NOT unguard a real protected push).
- PASS (exit 0): `git push origin feat/x`, both-unprotected compound, `--repo myrepo origin feat/x`,
  `git status`, `mygit push origin main`, implicit `git push` while OFF protected (on feat/safe).
- FAIL-CLOSED: unparseable stdin -> exit 2.
HAS_REFSPEC survives the heredoc read loop (loop body runs in parent shell), so the
implicit-current-branch path fires only for no-refspec pushes — confirmed by the two
implicit `git push` cases (off=0, on=2) and by refspec pushes never reaching that path.

## Test result (re-run by reviewer)
- `bash tests/hooks/protected-branch.test.bash` -> 31 assertions, 0 failed (GREEN). EXIT=0.
- `bash tests/hooks/run.sh` (full suite) -> 30 suites run, 0 failed.

## Verdict
APPROVE. The two LIVE push-gate bugs are closed with a tokenized action-trace walker that
mirrors the proven merge-targets.sh authority; no legitimate non-target push is newly
false-blocked; all previously-blocked inputs still block; fail-closed on unparseable input
preserved; in-lane only; lane and full suites green.
