verdict: approve

# Adversarial integration review — lane MG (feat/MG-merge-rebase-leftover)

Reviewer: adversarial integration reviewer (read-only), integrate skill Step 2.
Commit reviewed: 4186dc5 — "LANE MG: 統合関所に D6 (stale base・fail-closed) と D5 (leftover worktree advisory) を追加".
Files changed (in scope, 2 only): hooks/block-unreviewed-merge.sh, tests/hooks/block-unreviewed-merge-drift.test.bash.
hooks/lib/repo-drift.sh reused READ-ONLY (no diff). board.json untouched.

## Test re-run (by reviewer)

- New lane test (block-unreviewed-merge-drift.test.bash): 15 assertions, 0 failed (GREEN).
- Original block-unreviewed-merge.test.bash: 28 assertions, 0 failed (every prior behavior preserved).
- Full suite tests/hooks/run.sh: SUITES 30 run, 0 failed.
- bash -n clean on both changed files.

## Bug class actually closed (traced, not assumed)

The D6 signal is a real TOPOLOGY trace, not a string proxy: `git merge-base --is-ancestor <dest> <lane>`
plus `git rev-list --left-right --count <dest>...<lane>`. It cannot be fooled by a textual match the
way the P0 string-proxy bug was. This is the correct fix for the "stale-based lane silently reverts an
already-merged fix" class (incident 2026-06-25): git diff/status is computed vs HEAD, so D6 instead
asserts the destination tip is contained in the lane.

Concrete adversarial traces I ran against the installed git:

- Fresh lane (branched off current destination tip, then +1 commit): `is-ancestor HEAD lane` = 0 → PASS.
  Correct: a legitimate up-to-date lane is NOT false-blocked.
- Stale lane (main advanced 2-3 commits after the lane branched): `is-ancestor` = 1 (not ancestor)
  → exit 2 with rebase instruction and divergence "2  0" / "3 ...". Correct: behind-destination lane blocked.
- D6 ordering precedence: stale lane with NO review record → D6 fires FIRST and reports "stale base" +
  rebase, NOT "no review". Correct — fixing the base is the prerequisite, and re-review after rebase is
  explicitly instructed in the block message.
- Non-lane behind branch (`git merge hotfix/x`, main ahead, hotfix not a lane): exit 0. No false-block.
- Unresolvable lane ref (feat/ghost, no commit): D6 cannot compute → fail-OPEN, exit 0. No false-block.
- Non-merge / non-git command: exit 0, and the `BUM_SOURCE_ONLY` sourcing guard
  (`[ -n "${BUM_SOURCE_ONLY:-}" ] && return 0`) does NOT raise a "return outside function" error on a
  real (non-sourced) run under set -u — the `&&` short-circuits before reaching `return`. Confirmed.
- D5 leftover-worktree advisory: prints "worktree remove <path>" to stderr when a merged-but-leftover
  worktree exists, exit unchanged (0); silent when none. Never gates. Confirmed end-to-end and in trace.

## Findings

- [minor] DEST_REF selection: when the operator runs the merge from a NON-trunk branch (e.g. an
  integration branch) and a local origin/main ref exists, D6 compares the lane against origin/main
  rather than the actual merge destination (HEAD). A lane that is fresh wrt main but BEHIND the
  integration HEAD would pass. This is an UNDER-block (fail-open) gap, not a false-block, and matches the
  lane's documented "prefer HEAD; use drift_main_ref when HEAD is detached/non-trunk" posture and the
  fail-open-on-uncertainty principle. Acceptable for this lane; noted for a future tightening if
  integration-branch merges become common. No data is hidden and no legitimate merge is newly blocked.
- [minor] D6 fail-open keys on `merge-base --is-ancestor` exit codes (only a clean exit 1 = stale-block;
  any other non-zero = fail-open). Verified the 0/1/error semantics hold on the installed git. Correct
  no-false-block intent.

No blockers. No regression to the existing verdict reject/approve/no-review checks or the ADR-0005
suite-run path (28/28 original assertions preserved). Scope clean; lib reused read-only.

## Verdict

approve — the load-bearing D6 fix closes the stale-base revert class with an action/topology signal,
fails open on every no-grounds case (no false-block of a normal merge), and the D5 advisory never
changes the exit code. The only findings are minor (an intentional under-block coverage boundary).
