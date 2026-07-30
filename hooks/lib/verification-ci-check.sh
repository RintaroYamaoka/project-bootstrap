#!/usr/bin/env bash
# Server-side (CI) twin of block-merge-if-verification-unclosed.sh — ADR 0012.
#
# WHY: the local PreToolUse merge gate only fires on a local `git merge`. The GitHub
# "Merge pull request" button runs server-side and never invokes a local hook, so an
# OPEN verification plan can be merged via the web UI / API (ADR 0011 documented this
# as a follow-up hole). This entrypoint runs the SAME judgement — verification-plan.sh
# is the single authority — on CI, so it can be wired as a required status check and
# enforce on EVERY merge path (local / Merge button / API). enforce_admins=true on the
# branch protection closes the admin-bypass hole (ADR 0012 穴 2).
#
# Difference from the hook: the branch is resolved from git / CI env, NOT from a stdin
# PreToolUse JSON. Judgement logic is NOT duplicated — we call the lib (no signal drift).
#
# Branch resolution order: $1 arg > $GITHUB_HEAD_REF (PR head in Actions) > current branch.
#
# Exit codes (CI-friendly — never false-red a whole PR):
#   0  plan is closed, OR opt-in not adopted, OR no plan for this branch (fail-open:
#      server-side can't see lane-ness; requiring a plan on every PR would false-block
#      trivial docs PRs — the teeth are "a STARTED plan can't be merged OPEN").
#   1  plan exists for this branch but is OPEN / empty / has an unjustified DROP -> block.
#   (branch unresolved / no git -> 0, neutral: don't let an infra gap block merges.)

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=verification-plan.sh
. "$HERE/verification-plan.sh"

TOP="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -z "$TOP" ] && { echo "verification-ci-check: not a git repo — neutral pass." >&2; exit 0; }

# opt-in: only repos that adopted the verification flow. New docs/bootstrap/verification
# is preferred, legacy docs/bootstrap/verification still honoured (ADR 0020).
VERIF_DIR="$(resolve_docs_dir "$TOP" verification)"
[ -d "$VERIF_DIR" ] || { echo "verification-ci-check: verification directory not adopted (looked for docs/bootstrap/verification and docs/verification) — neutral pass." >&2; exit 0; }

BRANCH="${1:-}"
[ -z "$BRANCH" ] && BRANCH="${GITHUB_HEAD_REF:-}"
[ -z "$BRANCH" ] && BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
[ -z "$BRANCH" ] || [ "$BRANCH" = "HEAD" ] && { echo "verification-ci-check: could not resolve a branch — neutral pass." >&2; exit 0; }

PLAN="$(vplan_path_for_branch "$TOP" "$BRANCH")"

# No plan for this branch -> fail-open (see header). The local hook blocks plan-missing on
# LANE branches, but lane-ness (board/worktree) isn't observable server-side, so we only
# enforce on plans that exist. Documented limit in ADR 0012.
if [ ! -s "$PLAN" ]; then
  echo "verification-ci-check: no verification plan for branch \"$BRANCH\" ($PLAN) — neutral pass." >&2
  exit 0
fi

ROWS="$(vplan_row_count "$PLAN")"
if [ "$ROWS" = 0 ]; then
  echo "verification-ci-check: BLOCK — plan $PLAN has no test-case rows (an empty plan dresses up 'zero verification' as green)." >&2
  exit 1
fi

OPEN="$(vplan_open_rows "$PLAN")"
BAD="$(vplan_bad_drops "$PLAN")"

if [ -n "$OPEN" ] || [ -n "$BAD" ]; then
  echo "verification-ci-check: BLOCK — verification plan for \"$BRANCH\" is not closed ($PLAN)." >&2
  if [ -n "$OPEN" ]; then
    echo "" >&2
    echo "OPEN rows (TODO=not run / FAIL=failed / HUMAN=awaiting human):" >&2
    printf '  %s\n' "$OPEN" >&2
  fi
  if [ -n "$BAD" ]; then
    echo "" >&2
    echo "DROP rows missing a reason (deciding not to test needs a reason — no silent caps):" >&2
    printf '  %s\n' "$BAD" >&2
  fi
  echo "" >&2
  echo "Resolve each OPEN row to PASS (verified against its oracle) or a reasoned DROP, then re-push." >&2
  echo "Ask the kill-question once per PASS: 'could this stay green while a user is broken?' — if yes, the oracle is wrong (the mood trap)." >&2
  exit 1
fi

echo "verification-ci-check: OK — plan for \"$BRANCH\" is closed ($ROWS rows)." >&2
exit 0
