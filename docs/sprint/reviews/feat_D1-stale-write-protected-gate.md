# Adversarial integration review — lane D1 (feat/D1-stale-write-protected-gate)

verdict: approve

Reviewer: adversarial integration reviewer (read-only), integrate skill Step 2
Worktree: /home/rintaroyamaoka/dev/my-projects/wt-D1-stale
Commit: f52b065 — "feat(D1): block stale trunk pushes with a freshness gate"
Date: 2026-06-25

## Scope / hygiene (PASS)
- 7 files changed, all in lane scope: hooks/block-stale-write-to-protected.sh (new),
  hooks/lib/repo-drift.sh (extended), the two test files, ADR 0009, two incident READMEs.
- hooks/hooks.json NOT touched (wiring left to lead, by design). docs/sprint/board.json NOT
  touched. No stray files (no .gate). Explicit pathspec used.
- Commit message ends with the required Co-Authored-By line.
- bash -n clean on both new bash files. (shellcheck not installed in env.)

## Test re-run (GREEN — I re-ran them myself)
- repo-drift.test.bash: 20 assertions, 0 failed.
- block-stale-write-to-protected.test.bash: 14 assertions, 0 failed.
- Full suite (bash tests/hooks/run.sh): 32 suites run, 0 failed. No existing suite regressed.

## Falsification attempts — signal design (string-proxy holes)
Traced live inputs through the real hook against a real file:// remote/clone fixture (no
network), local stale-vs-remote by N=2..4:
- `git push origin main` (stale)            -> exit 2  (intended block)
- `git push` implicit current==trunk        -> exit 2  (implicit-current-branch path works)
- `git push origin HEAD:main`               -> exit 2  (src:dst dst normalized)
- `git push origin mywork:main`             -> exit 2  (src:dst, dst is trunk)
- `git push --force origin main` / `+main`  -> exit 2  (force / leading-+ stripped)
- `/usr/bin/git push origin main`           -> exit 2  (path-prefixed git caught — the
                                                        greedy-sed/no-leading-slash class is
                                                        closed via reused protected-branch.sh)
- `git push origin feat/x && git push origin main` -> exit 2 (compound: trunk hidden after a
                                                        feature push still caught; not the
                                                        last-segment-only bug)
- `git push origin feat/x main` (2 refspecs) -> exit 2 (every destination enumerated)
- `git push -o main origin feat/x`          -> exit 0  (flag VALUE "main" is NOT mis-read as a
                                                        destination — argument-skip works;
                                                        no false-block)
No string-proxy hole found: detection reuses lib/protected-branch.sh
(cmd_has_git_push + push_destination_branches), the same single authority that fixed this
repo's path-prefixed/greedy-sed bug. Inherited known limit (separator metachar inside a
quoted arg) is documented in the ADR and is fail-OPEN for that one input.

## Falsification attempts — fail-mode (no false-block / fail-open / fail-closed)
- non-trunk feature push while stale        -> exit 0 (fail-open; feature work never disturbed)
- plain push while on a non-trunk branch     -> exit 0 (implicit-current not trunk)
- fresh trunk push (behind 0)                -> exit 0 (fail-open)
- fetch fails (origin url -> nonexistent path) -> exit 0 (offline fail-OPEN; work never blocked)
- no resolvable trunk ref (solo, no remote)  -> exit 0 (drift_main_ref returns 1 -> fail-open)
- non-push git / non-git command             -> exit 0
- unparseable input (no command key)         -> exit 2 (fail-CLOSED, parse-impossible)
behind-guard robustness: `[ "$BEHIND" -gt 0 ] 2>/dev/null` traced with BEHIND in {"", "abc",
"0", "3"} -> only "3" blocks; empty/non-numeric/0 all fail-OPEN. fetched_behind_count itself
normalizes its echo to an integer or "0", so the gate cannot block on garbage.

## Falsification attempts — the staleness engine (single authority, real fetch, bounded)
- fetched_behind_count DOES fetch: with a stale local clone, offline behind_count=0 while
  fetched_behind_count=2 on the same repo; local refs/remotes/origin/main advanced after the
  call. So the count is authoritative, not a stale-ref read.
- distinct fetch-failure signal: nonexistent remote -> rc=1 (gate fails OPEN); nonexistent
  remote branch -> rc=1. Confirmed in both the lib test and direct calls.
- explicit refspec is bounded: after adding other-branch/decoy-feature on the remote, fetching
  only `main` left those tracking refs ABSENT locally — cannot become an unbounded sync.
- leading `+` (force) refspec: a rewound remote tip still force-updates the tracking ref and
  yields a correct count (rc=0), not a fetch error.
- timeout present in this env (/usr/bin/timeout); both timeout and timeout-absent arms reach
  the same `|| return 1` fail-open. The timeout-absent unbounded-wait risk is documented in
  the ADR as a known limit.
- offline path untouched: the only removed line in repo-drift.sh is the behind_count HEADER
  comment (expanded to add the OFFLINE note). The behind_count() body and drift_report are
  byte-for-byte unchanged — the doctor's no-network contract is preserved.

## Falsification attempts — non-duplication with block-push-to-protected (D1-specific)
Read both gates. block-push-to-protected keys on `.bootstrap-protected` membership and blocks
DIRECT protected pushes outright (freshness irrelevant); D1 keys on the trunk that
drift_main_ref resolves (origin/main->main) and enforces FRESHNESS of an otherwise-allowed
trunk push. Orthogonal signals, no overlap. Both read git context from cwd (not the JSON cwd
field) — same proven pattern; run_hook cds into RUN_DIR mirroring the harness. ADR 0009
articulates the non-duplication AND the after-block-push-to-protected ordering.

## Findings
- MINOR (not a blocker, sanctioned by spec): the destination match is by branch NAME only
  (`dst == TRUNK_BRANCH`), ignoring the remote. So `git push backup main` (a non-trunk remote,
  e.g. a personal fork) while behind origin/main BLOCKS, and the remedy message names `origin`.
  This is intended ("destination equals the trunk branch") and the behind count is still
  measured against the real trunk, so it does not block in the wrong direction and is arguably
  still the right risk class to gate; worth a one-line note if remote-aware matching is ever
  wanted. Does not affect integration.

## Conclusion
No blocker. Signal is the ACTION + a physical staleness trace (post-fetch behind>0), not a
string proxy. Fail-modes are deliberate and correct: parse-impossible fail-CLOSED; every
no-grounds path (non-push / no work-tree / trunk unresolvable / non-trunk dest / fetch-fail /
behind==0) fails OPEN and is announced. The online/offline staleness authority is single and
the doctor path is untouched. Tests are real fixtures and GREEN; full suite unbroken.
APPROVE for integration (lead wires the PreToolUse(Bash) hook after block-push-to-protected).
