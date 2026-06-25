#!/usr/bin/env bash
# Configure GitHub SERVER-SIDE enforcement so the verification gate covers every merge path
# (ADR 0012). The local PreToolUse merge hook is only a fast feedback layer — it cannot stop a
# merge done via the GitHub "Merge pull request" button (server-side). This script makes the
# durable layer:
#   1. Branch protection on the protected branch with:
#        - required status check  = "verification-closed"  (the CI twin of the merge gate)
#        - enforce_admins = true   (穴 2: a single orchestrator must NOT bypass their own gate)
#        - required PR review      (1 approval)
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

REPO="" BRANCH="main" CHECK_CONTEXT="verification-closed" WANT_QUEUE=0 CHECK_ONLY=0

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
  if ! gh api "repos/$REPO/branches/$BRANCH/protection" >/tmp/_bp.json 2>/dev/null; then
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

# --- APPLY: branch protection with required check + enforce_admins + review -----------------
echo "→ setting branch protection (required check '$CHECK_CONTEXT', enforce_admins=true, 1 review)…"
gh api -X PUT "repos/$REPO/branches/$BRANCH/protection" \
  -H "Accept: application/vnd.github+json" \
  --input - >/dev/null <<JSON
{
  "required_status_checks": { "strict": true, "contexts": ["$CHECK_CONTEXT"] },
  "enforce_admins": true,
  "required_pull_request_reviews": { "required_approving_review_count": 1 },
  "restrictions": null
}
JSON
echo "  ✓ branch protection applied (enforce_admins=true — the orchestrator can't bypass)."

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
