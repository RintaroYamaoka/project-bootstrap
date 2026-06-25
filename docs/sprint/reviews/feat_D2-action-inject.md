verdict: approve

# Adversarial integration review — lane D2 (feat/D2-action-inject)

Reviewer: adversarial integration reviewer (read-only). Branch read trying to falsify it.
Commit reviewed: 0ce978c (`git diff main...feat/D2-action-inject`). Worktree: /home/rintaroyamaoka/dev/my-projects/wt-D2-inject.

## Scope / out-of-scope discipline — CLEAN
- Files changed (7) are exactly the lane deliverables: `hooks/lib/action-gate.sh`, `hooks/inject-action-memory.sh`, `templates/bootstrap-actions.example`, `scripts/doctor.sh`, `skills/incident/SKILL.md`, `docs/decisions/0010-inject-memory-at-repeat-prone-action.md`, `tests/hooks/action-gate.test.bash`.
- `hooks/hooks.json` NOT touched (verified: empty diff). `docs/sprint/board.json` NOT touched. No out-of-lane edits.

## Tests RE-RUN by reviewer
- `bash tests/hooks/action-gate.test.bash` -> 38 assertions, 0 failed (matches report).
- `bash tests/hooks/run.sh` (full suite) -> SUITES: 32 run, 0 failed. Existing doctor/verification/merge tests still green after the doctor.sh change.
- `bash -n` syntax-clean on action-gate.sh, inject-action-memory.sh, doctor.sh.

## Cardinal invariant: NEVER exit 2 — HOLDS
Probed every path of inject-action-memory.sh with empty stdin, garbage, no-command, null command, empty command, unterminated JSON string, embedded quote/brace, embedded newline, non-Bash tool. ALL exit 0, no stderr noise. The `set -u` + `parse_command || exit 0` + per-stage `[ -n ] || exit 0` + trailing `exit 0` chain has no path that can reach a nonzero exit, let alone 2. The dedicated test "armed match NEVER exits 2" confirms the most-tempted (matched+armed) path is exit 0.

## Matcher is controlled-vocab, NOT per-entry regex — CONFIRMED (the key design constraint)
- `hooks/lib/action-gate.sh` is a single-authority tokenizer (modeled on merge-targets.sh) mapping to a CLOSED `ACTION_KEY_ENUM="prod-deploy prod-db-migrate"`. The registry only ARMS an existing key; it carries no match pattern.
- grep'd the lib for `eval` / user-regex-from-registry / `$(...$line...)`: NONE. Registry parsing is pure bash parameter-expansion trimming; slug/note are printed verbatim, never used as a pattern. No greedy-sed / string-proxy re-import, no code-injection from a registry line (memo containing `"` / `\` / `}` still yields valid JSON — verified).
- Adding a key is a reviewed plugin-level edit to the array + matcher arm + test, exactly as specified.

## String-proxy hole hunt (the bug class this repo already fixed) — NO HOLES that false-fire
Traced path-prefixed / compound / env-prefixed / launcher / quoting forms:
- MATCH (correct): `vercel deploy --prod`, `--production`, flag-before-subcommand, `/usr/local/bin/vercel ...`, `npx vercel ...`, `pnpm dlx vercel ...`, `CI=1 VERCEL_TOKEN=x vercel ...`, `npm run build && vercel deploy --prod` (second segment), `bash -c "vercel deploy --prod"`, `prisma migrate deploy`, `DATABASE_URL=x ./node_modules/.bin/prisma migrate deploy`.
- NO false-match: `vercel deploy` (preview, no --prod), `vercel --prod` (no subcommand), `echo deploy --prod to production`, `git status`, `prisma generate`, `prisma migrate dev`, `mygit merge`, `echo vercel deploy --prod` (vercel is an arg not head), `which vercel deploy --prod`, `git deploy --prod`.
- State does NOT leak across compound segments (the most dangerous false-trigger): `echo deploy && vercel --prod` -> [], `vercel deploy && echo --prod` -> [], `echo --prod && vercel deploy` -> []. Per-segment facts reset at each `;SEP;`. This is the spot a naive matcher would false-fire; it does not.
- `git commit -m "deploy --prod" && vercel deploy --prod` correctly matches the REAL second segment despite the decoy in the quoted message.

## Fail-mode polarity — correct (all fail-OPEN/silent; no irreducible judgment forced, no benign block)
- No registry (opt-in) / unarmed key / no enum match / parse failure / tokenizer mis-split on a quoted separator -> all exit 0 silent. A non-adopting repo is never disturbed (verified: doctor and hook both silent without `.bootstrap-actions`).
- The one documented limit (quoted separator splits a segment, e.g. `vercel deploy -m "a && b" --prod` -> []) lands on the SAFE side for a visibility hook: a possibly-MISSED memo, never a wrong block. Documented in lib header + ADR 0010 + the merge-targets.sh precedent. Correct polarity (a blocking gate would fail-closed here; this one has no unsafe side, so fail-open is right).
- TTL polarity is SAFE-side: no self-disarm TTL is added; ADR 0010 records that any future expiry must re-surface louder + be listed by doctor, never silently disarm. Matches the constraint.

## Single-authority / no-drift — CONFIRMED
doctor.sh sources the SAME `hooks/lib/action-gate.sh` the hook uses (`registry_orphan_keys`, `action_key_is_known`), so "what is a valid key" cannot drift between the injector and the audit. noglob (`set -f`) is correctly saved/restored by the tokenizer — verified no leak into doctor's environment after sourcing+calling.

## Doctor audit — surface-only, never flips status (per spec)
Ran doctor.sh against four fixtures: (A) clean-armed -> "actions: ... (2 armed, no orphans)" + STATUS ok; (B) orphan key `not-a-key` -> surfaced with "memo can never fire" hint; (C) no registry but a `repeat-action`-tagged incident -> arm-gap surfaced; (D) no registry + no tag -> SILENT (no actions line). Status never flips to partial from the actions line; the early-return for skip/unadopted/declined sits BEFORE the audit block, so non-adopting repos never reach it. doctor runs `set -u` only (no `set -e`), so the audit's nonzero grep/cd cannot abort it.

## JSON shape — correct
Output is `{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"..."}}`, the same shape as bootstrap-session-doctor.sh (which uses SessionStart; PreToolUse here is correct for a PreToolUse hook). Validated as well-formed JSON via python including a memo body carrying `"`, `\`, `}` and newlines — escaping (backslash, then quote, then newline) is in the right order and survives.

## Findings (all non-blocking)
- minor: `bash -c "..."` unwrap is an approximation (de-quotes tokens, treats the script's first word as segment head); covers single-verb keys, does not fully parse arbitrary nested shells. Documented in lib header + ADR; fail-open (a miss, never a wrong block). Acceptable for a visibility hook.
- minor: no `tests/hooks/doctor.test.bash` case for the new `actions:` line (that file is outside lane D2 scope). Reviewer manually exercised orphan / clean-armed / incident-no-registry / silent states and confirmed existing doctor tests still pass. Lead may add a doctor-side case at integration.
- minor (integration, not lane): lead must wire `inject-action-memory.sh` as a PreToolUse(Bash) hook in hooks/hooks.json (correctly NOT done in-lane per the hard rule). Until wired, the mechanism is inert — but that is the integration step, not a lane defect.

## Verdict
APPROVE. The lane meets every hard design constraint: never exits 2, controlled-vocabulary tokenizer (no per-entry regex, no eval), all-fail-open/silent with correct polarity, TTL safe-side, single-authority lib shared by hook+doctor, doctor surface-only. No string-proxy hole that false-fires, no benign-action block, no forced irreducible judgment. Tests re-run green (38/0 lane, 32/0 suite). No existing behavior broken, no out-of-scope or hooks.json edits.
