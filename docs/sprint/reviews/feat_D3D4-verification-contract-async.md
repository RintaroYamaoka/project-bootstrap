verdict: approve

Lane D3D4 — cross-repo contract drift gate (D3, ADR 0011) + async/silent-skip doctrine (D4, ADR 0007 amendment)
Branch: feat/D3D4-verification-contract-async  Worktree: /home/rintaroyamaoka/dev/my-projects/wt-D3D4-verif  Commit: f058e15 → adeea41 (anchor fix)

> Re-review note (anchor fix, commit adeea41): the MAJOR string-proxy hole flagged below is now FULLY
> CLOSED and re-verified end-to-end. Verdict upgraded from "approve with MAJOR flagged for fast follow-up"
> to a clean **approve** — no surviving blocker, no new hole. The original review body is kept below for
> context; the trace evidence for the fix is in the "Re-review (anchor fix)" section at the bottom.

Adversarial review. I read the full committed diff, re-ran every lane test myself, and traced both the
intended behavior AND the fail-open / no-false-trigger cases with live fixtures at the exact PreToolUse
merge-hook runtime condition (HEAD on main). Verdict approve: the D3 critique blocker is genuinely fixed,
D4 keys on the controlled-vocab field (not prose), nothing out of scope, full suite green. One MAJOR
string-proxy hole in the contract-close matcher is flagged for a fast follow-up (not a blocker — the
common case is correct and the existing plan-OPEN check backstops many configurations).

## Tests re-run (by me, not trusting the report)
- bash tests/hooks/cross-repo-contract.test.bash            -> 19/19, exit 0
- bash tests/hooks/verification-plan.test.bash              -> 30/30, exit 0
- bash tests/hooks/verification-drift.test.bash             -> 16/16, exit 0
- bash tests/hooks/block-merge-if-verification-unclosed.test.bash -> 29/29, exit 0
- bash tests/hooks/run.sh (FULL suite)                      -> 32 suites, 0 failed, exit 0
- shellcheck -S warning on all 4 new/modified .sh           -> exit 0, no warning-or-above
Worktree clean, single commit ahead of main, correct Co-Authored-By trailer.

## Scope / hygiene
- Changed files all within lane scope (.bootstrap-lane). hooks/hooks.json NOT touched; docs/sprint/board.json NOT touched.
- D3 extends the EXISTING hook block-merge-if-verification-unclosed.sh (spec-required), AFTER the plan checks. Existing plan behavior preserved (the pre-lane plan-check cases still pass unchanged).
- D4 doctor axis 2 is wired: bootstrap-session-doctor.sh already calls verification_drift_report, so axis 2 runs at SessionStart with no hooks.json edit. block-merge gate already wired in hooks.json (1 entry).

## Sample traces (live fixtures, the real merge-hook condition)
- D3 LANE-delta-not-cwd/HEAD (the critique blocker): built a repo, made a lane branch touching a declared
  face, then `git checkout main` so HEAD = merge destination (the PreToolUse condition). Ran the hook:
  it BLOCKED (exit 2, names "demo-survey-schema"). This proves branch_changed_sources computes
  base..lane OFFLINE via merge-base, NOT cwd/HEAD (which would be empty on main → silent no-op). Confirmed.
- D3 free-text PASS cannot close: a plan generically closed by an UNRELATED reasoned DROP still blocks
  because no row references the touched contract id (gate test 19 + my trace A). A PASS/DROP row that
  DOES reference the id closes it; an OPEN (TODO/HUMAN) row referencing it does NOT (stays OPEN → blocks).
- D3 fail-open (all verified): no contracts file → axis silent; lane touches no declared face → no-grounds
  silent; phantom board branch with NO git ref → branch_changed_sources empty → contract axis no-op
  (closed plan passes, exit 0); non-git / docs/verification not adopted → exit 0. Consumer-side only: the
  lib never reads/diffs the sibling (peer_repo/peer_face are human hints), so a machine lacking the sibling
  checkout raises no false alarm. Governing-side no-op (downstream-only change → no lane branch here) is
  documented in ADR 0011 + the header, not silently implied as covered.
- D3 suite-run move: NEEDS_CONTRACT_SUITE triggers detect-test-suite.sh (shared with the review gate, ADR
  0005 guard 1) and blocks on red; fail-open when no runner is detectable (the HUMAN-row path is the
  documented backstop). No network call anywhere (offline; drift_main_ref reads the LOCAL origin ref, falls
  back to HEAD) — fetch-fail/offline under-reports, never false-alarms.
- D4 doctor keys on the kind field, not prose: a DROP row whose behaviour text contains "drop / skip /
  filter" does NOT fire the async advisory (the old lexicon-scan false-fire is gone) — vplan_has_kind does
  an EXACT, case-folded, whole-field-2 match, never a substring scan of prose. Verified: a row whose prose
  contains "monitor"/"drop" does not register as that kind.
- D4 placement: axis 2 fires on POPULATED plans, AFTER the source-face-change gate (`changed` non-empty)
  and BEFORE the empty-plan early-return — so it is silent on docs-only branches (test 13) and silent when
  a real monitor (field-4 != n/a) backs the async row; a placeholder (n/a) monitor still fires (test 14).
  Advisory only: verification_drift_report returns 0 even when it fires (test 15). Never exits 2.

## Findings

### MAJOR — contract-close matcher is a raw substring scan (string-proxy hole; reachable through the full gate)
hooks/lib/cross-repo-contract.sh, crc_closed_row_references_id():
    case "$line" in *"$id"*) return 0 ;; esac
It tests whether the id appears ANYWHERE in the raw plan line, with no `[contract:<id>]` anchor and no word
boundary. Two false-CLOSE holes, both verified end-to-end through block-merge-if-verification-unclosed.sh
(not just the unit helper):
  (1) id-substring collision: touched id "booking" is falsely closed by a row that references the SUPERSTRING
      id "booking-payload". Live gate trace: touched="booking", plan closes only "booking-payload" → gate
      returns exit 0 (PASSES) where it MUST block (exit 2). An unverified cross-repo break merges silently.
  (2) common-word collision: an id like "survey" is falsely closed by any PASS/DROP row whose prose merely
      mentions "survey" (e.g. "we test the survey rendering logic"). Verified at the helper level (false close).
Why this matters: this is exactly the "string proxy with holes" the review hunts, and it CONTRADICTS the
lane's own D4 doctrine baked into this same commit ("key ONLY on the controlled-vocab field the AI set,
NEVER a substring scan" — verification-plan.sh / verification-drift.sh). The header even asserts "Substring
match is intentional here" while the sibling D4 change exists precisely because substring scans false-fire.
Direction of failure is fail-OPEN inside a fail-CLOSED gate (it lets a touched-but-unclosed contract merge),
which is the worse direction for this gate.
Not a blocker because: the common case (a single, specific id with no superstring sibling and no prose
collision — e.g. the template's "demo-survey-schema") works correctly, as traces A/B show; the existing
plan-OPEN check backstops configurations where the touched contract has its own unreferenced OPEN row; and
the convention `[contract:<id>]` already exists. Fast fix: match the anchored token `[contract:<id>]`
(or require a delimiter boundary) instead of a bare substring — single-line change, fully in lane scope.

### MINOR — suite-red block path has no test
The "contract acknowledged → gate runs the suite → suite RED → block (exit 2)" branch
(NEEDS_CONTRACT_SUITE, block-merge-if-verification-unclosed.sh ~L211-230) is not exercised by any test in
this lane: every fixture runs in a temp repo with no detectable runner, so detect_test_command returns 1 and
the suite step is skipped (the documented fail-open). The logic mirrors the proven ADR 0005 guard 1 path in
block-unreviewed-merge.sh, so it is reuse of an exercised pattern — but the D3-specific red→block edge is
asserted nowhere. Consider one fixture with a trivial package.json `"test"` that exits non-zero.

### MINOR — D4 amendment lives in 0011 + SKILL.md, not appended to ADR 0007
0007-*.md is out of this lane's edit scope (.bootstrap-lane grants only docs/decisions/0011-*.md), so the D4
amendment note sits in 0011's "Amendment ノート" section and the two SKILL.md files (the implementation 正本)
rather than at 0007's tail. This is correctly flagged by the implementer and is consistent with the lane
boundary; a future lane with 0007 in scope should transcribe it. Acceptable as-is — recording the limit,
not a defect.

### MINOR — oracle field with a literal '|' truncates (pre-existing, not introduced)
vplan_field uses `cut -d'|'`, so a monitor oracle containing a literal pipe truncates at the first pipe.
_vd_has_real_monitor only needs the oracle non-empty/non-n/a, so a truncated-but-present oracle still
correctly counts as real → no regression. This is the pre-existing plan format constraint shared by all
consumers, not introduced by this lane. Noted for completeness only.

## Conclusion
No blocker. The D3 critique blocker (LANE-delta vs cwd/HEAD) is genuinely fixed and traced live; free-text
PASS cannot close a touched contract via a generic plan close; all fail-open / no-grounds cases behave as
designed and never false-alarm on non-target or sibling-less machines; D4 keys on the controlled-vocab kind
field (no prose false-fire), sits after the source-face gate and before the early-return, and is strictly
advisory. The MAJOR contract-id substring hole should be fixed in a fast follow-up (anchor on
`[contract:<id>]`) because it is the precise string-proxy class this repo treats as a first-class bug and it
fails OPEN — but it does not break the common path and is one line to close. Approving with that flagged.

---

## Re-review (anchor fix) — commit adeea41, by an adversarial re-reviewer

The fast-follow fix landed. I re-reviewed the diff, re-ran the lane + full suite, traced the holes
end-to-end through `block-merge-if-verification-unclosed.sh`, ran my own adversarial matrix against the
new matcher, and proved the new tests are genuinely TDD-red on the pre-fix lib. **The MAJOR is fully
closed with no new blocker and no new hole. Verdict: approve.**

### What the fix does (hooks/lib/cross-repo-contract.sh, crc_closed_row_references_id)
The bare `case "$line" in *"$id"*` substring scan is replaced by a verbatim match of the anchored
literal tag `[contract:<id>]`. The id is folded char-by-char into the `case` PATTERN with every glob
metacharacter (`* ? [ ] \`) escaped, and the surrounding brackets are escaped (`\[ ... \]`) so they are
literal, not a `case` bracket-expression. The trailing `]` is part of the needle, so the superstring
boundary is enforced for free. Status gate (PASS/DROP only) is unchanged. Pure bash, jq-free, no regex.

### Tests re-run (by me, not trusting the report)
- bash tests/hooks/cross-repo-contract.test.bash                  -> 31 assertions, 0 failed, exit 0
- bash tests/hooks/verification-plan.test.bash                    -> 30, 0 failed
- bash tests/hooks/verification-drift.test.bash                   -> 16, 0 failed
- bash tests/hooks/block-merge-if-verification-unclosed.test.bash -> 29, 0 failed
- bash tests/hooks/run.sh (FULL suite)                            -> 32 suites, 0 failed
Worktree clean; only the 4 declared files changed (diff f058e15..adeea41); hooks/hooks.json and
docs/sprint/board.json untouched; all 4 files within `.bootstrap-lane`. Correct Co-Authored-By trailer.

### TDD-first proof (the new cases are genuinely red on the pre-fix lib)
I restored the lib to its pre-fix version (f058e15) and ran the new test file: **exactly 5 assertions
fail**, then 0 fail after restoring the fixed lib. The 5 reds are precisely the bug, two of them through
the real merge gate:
  1. unit: 'booking' IS closed by a 'booking-payload' row (got rc 0, want 1)
  2. unit: 'survey' IS closed by prose mentioning 'survey' (got rc 0, want 1)
  3. e2e: gate does NOT block on the booking/booking-payload hole (got exit 0, want 2)
  4. e2e: the (missing) block does not name the id (because it didn't block)
  5. e2e: gate does NOT block on the survey-prose hole (got exit 0, want 2)

### End-to-end traces through block-merge-if-verification-unclosed.sh (the real gate, linked-worktree lane)
- Touched id `booking`, plan acknowledges ONLY `[contract:booking-payload]` → gate BLOCKS, exit 2,
  stderr names "booking". (Was exit 0 / silent-merge before the fix.) **Closed.**
- Touched id `survey`, plan only has a PASS row whose prose says "the survey looked fine" with NO tag →
  gate BLOCKS, exit 2. (Was exit 0 before.) **Closed.**
- Touched id `booking`, plan carries the correctly anchored `[contract:booking]`, no detectable runner →
  contract axis PASSES, gate exits 0 (clean merge). Positive control holds.
- The previously-untested **suite-red→block** edge (prior MINOR) is now asserted: with npm on PATH, a
  fixture package.json whose `test` script exits non-zero is detected, the gate RUNS it, the suite is RED
  → gate BLOCKS exit 2 with "test suite fails". (npm IS present in this env, so it ran — not skipped.)

### Adversarial hole-hunt on the new anchoring (17 probes, all correct)
I drove crc_closed_row_references_id directly with hostile inputs to find any hole the anchoring might
have opened. ALL behave correctly:
- case sensitivity holds: `[contract:Booking]` does NOT close id `booking` (literal, case-sensitive).
- every glob metachar in an id is literal: `a*b` matches `[contract:a*b]` but NOT `[contract:aXXb]`;
  `a?b` ≠ `axb`; ids containing `[`, `]`, `\` round-trip and match only themselves.
- boundary holds both ways: `booking` ≠ `booking-payload` and `user`/`profile` ≠ `user-profile`.
- partial tag with no closing bracket (`[contract:booking`) does NOT close (needle requires the `]`).
- spaced tag `[contract: booking ]` does NOT close `booking` (strict literal — acceptable, the
  convention/docs show no spaces; not a false-CLOSE so it errs to the safe fail-closed side).
- uppercase keyword `[CONTRACT:booking]` does NOT close (the `contract:` keyword is literal — also safe).
- status still wins: the tag inside a TODO/HUMAN/FAIL row does NOT close (stays OPEN → blocks); only
  PASS/DROP rows with the tag close. Multi-tag rows close each tagged id and only those.
No new hole found. The only behavioural tightenings (spaced/uppercase variants don't close) all fail
SAFE (toward block), never toward a silent merge.

### Doc/code consistency (no drift between convention and matcher)
- skills/verification/SKILL.md now states a CLOSED cross-repo row MUST carry the literal `[contract:<id>]`
  tag (bare prose / another id's substring won't close), citing the same D4 controlled-vocab doctrine. Its
  example row already uses `[contract:demo-survey-schema]`.
- templates/docs/verification/contracts.example now documents the bracketed tag and the substring caveat
  with the exact booking/booking-payload example.
- ADR 0011 (pre-existing) already specified `[contract:<id>]`, and the block-merge gate's own remediation
  text already told authors to write `[contract:$CID]` — the matcher now matches what every doc says.
- The merge gate's existing positive fixture already used `[contract:demo-survey-schema]` (from f058e15),
  so it stays green under the stricter matcher — no fixture was loosened to make the fix pass.

### Findings (re-review)
- MAJOR (string-proxy substring hole): **RESOLVED** — anchored on the literal `[contract:<id>]` tag,
  verified by unit + e2e + 17-probe matrix + TDD-red proof.
- MINOR (suite-red→block path untested): **RESOLVED** — now asserted end-to-end (case ran, npm present).
- MINOR (D4 amendment in 0011/SKILL.md not appended to ADR 0007): unchanged — 0007 is out of lane scope;
  correctly deferred to a future lane. Not a defect.
- MINOR (vplan_field `cut -d'|'` truncates a literal-pipe oracle): unchanged, pre-existing, no regression.
No new blocker introduced. **Verdict: approve.**
