#!/usr/bin/env bash
# Configure GitHub SERVER-SIDE enforcement so the verification gate covers every merge path
# (ADR 0012). The local PreToolUse merge hook is only a fast feedback layer — it cannot stop a
# merge done via the GitHub "Merge pull request" button (server-side). This script makes the
# durable layer:
#   1. Branch protection on the protected branch with:
#        - required status checks = "verification-closed" + "hooks"  (CI twin of the merge
#                                   gate + the hook test suite)
#        - enforce_admins = true   (穴 2: a single orchestrator must NOT bypass their own gate)
#        - require a PR before merging, but 0 required approvals — a SOLO orchestrator can't
#          approve their own PR, so requiring a human approval would lock them out. The PR +
#          required checks still force every change through the gate; AI review is enforced
#          separately by the local block-unreviewed-merge hook (trust ladder Stage 2).
#   2. (opt-in) Merge queue — re-validates each PR against the LATEST target branch, catching
#      stale-lane integration breakage the local pre-merge hook can't see (穴 3).
#
# Idempotent: re-running converges to the same state. Requires `gh` authenticated with admin.
#
# Usage:
#   scripts/setup-server-enforcement.sh                 # current repo, branch=main
#   scripts/setup-server-enforcement.sh -r owner/repo -b main
#   scripts/setup-server-enforcement.sh --merge-queue   # also enable merge queue
#   scripts/setup-server-enforcement.sh --check         # CHECK ONLY — interrupt (admin bypass?)
#
# This is an outward-facing change to a repo's merge policy. With --check it only reports.

set -euo pipefail

REPO="" BRANCH="main" CHECK_CONTEXT="verification-closed" EXTRA_CONTEXT="hooks" WANT_QUEUE=0 CHECK_ONLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    -r|--repo)        REPO="$2"; shift 2 ;;
    -b|--branch)      BRANCH="$2"; shift 2 ;;
    -c|--context)     CHECK_CONTEXT="$2"; shift 2 ;;
    --merge-queue)    WANT_QUEUE=1; shift ;;
    --check)          CHECK_ONLY=1; shift ;;
    -h|--help)        sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

command -v gh >/dev/null 2>&1 || { echo "error: gh CLI not found." >&2; exit 1; }

if [ -z "$REPO" ]; then
  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
  [ -z "$REPO" ] && { echo "error: not in a gh repo and no -r given." >&2; exit 1; }
fi

echo "repo=$REPO branch=$BRANCH required-check=$CHECK_CONTEXT merge-queue=$WANT_QUEUE check-only=$CHECK_ONLY"

# --- CHECK ONLY: report current protection (does the admin bypass their own gate?) ----------
if [ "$CHECK_ONLY" = 1 ]; then
  # per-invocation temp file (a fixed /tmp path collides across users/parallel runs and
  # leaves litter); trap cleans it up on any exit.
  BP_JSON="$(mktemp "${TMPDIR:-/tmp}/bp-protection.XXXXXX")"
  trap 'rm -f "$BP_JSON"' EXIT
  if ! gh api "repos/$REPO/branches/$BRANCH/protection" >"$BP_JSON" 2>/dev/null; then
    echo "  ⚠ NO branch protection on $REPO@$BRANCH — server-side gate is OPEN (Merge button bypasses the local hook)."
    exit 0
  fi
  admins="$(gh api "repos/$REPO/branches/$BRANCH/protection/enforce_admins" -q .enabled 2>/dev/null || echo unknown)"
  checks="$(gh api "repos/$REPO/branches/$BRANCH/protection/required_status_checks" -q '.contexts | join(",")' 2>/dev/null || echo '')"
  echo "  branch protection: present"
  echo "  enforce_admins   : $admins   $([ "$admins" = true ] || echo '⚠ admin can bypass the gate (穴 2)')"
  echo "  required checks  : ${checks:-<none>}   $(printf '%s' "$checks" | grep -q "$CHECK_CONTEXT" || echo "⚠ '$CHECK_CONTEXT' not required (穴 1)")"
  exit 0
fi

# --- APPLY: branch protection with required checks + enforce_admins + PR-required ----------
echo "→ setting branch protection (required checks '$CHECK_CONTEXT'+'$EXTRA_CONTEXT', enforce_admins=true, PR required, 0 approvals)…"
gh api -X PUT "repos/$REPO/branches/$BRANCH/protection" \
  -H "Accept: application/vnd.github+json" \
  --input - >/dev/null <<JSON
{
  "required_status_checks": { "strict": true, "contexts": ["$CHECK_CONTEXT", "$EXTRA_CONTEXT"] },
  "enforce_admins": true,
  "required_pull_request_reviews": { "required_approving_review_count": 0 },
  "restrictions": null
}
JSON
echo "  ✓ branch protection applied (enforce_admins=true — the orchestrator can't bypass; PR required, 0 human approvals so a solo dev isn't locked out)."

# Belt-and-suspenders: the full-protection PUT has been observed to keep only the first
# context in some cases. Assert the required contexts explicitly via the dedicated endpoint.
gh api -X PATCH "repos/$REPO/branches/$BRANCH/protection/required_status_checks" \
  --input - >/dev/null <<JSON
{ "strict": true, "contexts": ["$CHECK_CONTEXT", "$EXTRA_CONTEXT"] }
JSON
echo "  ✓ required checks asserted: $(gh api "repos/$REPO/branches/$BRANCH/protection/required_status_checks" -q '.contexts | join(", ")')"

# --- (opt-in) merge queue ------------------------------------------------------------------
if [ "$WANT_QUEUE" = 1 ]; then
  echo "→ enabling merge queue (re-validate each PR against latest $BRANCH — catches stale-lane breakage, 穴 3)…"
  # Merge queue is configured via branch protection's required_status_checks + the repo's
  # "Require merge queue" setting. The GraphQL/REST surface varies; we enable via the
  # branch-protection rule's merge_queue where available, else instruct the human.
  if gh api -X PATCH "repos/$REPO/branches/$BRANCH/protection/required_status_checks" \
       -f 'checks[][context]'="$CHECK_CONTEXT" >/dev/null 2>&1; then :; fi
  echo "  ℹ Enable 'Require merge queue' on the branch rule in Settings → Branches (or via a ruleset)."
  echo "    Merge queue toggling is not fully exposed on the REST branch-protection endpoint;"
  echo "    use a repository ruleset (templates/github/ruleset.json) for fully-scripted setup."
fi

echo "done. Verify with: $0 -r $REPO -b $BRANCH --check"
