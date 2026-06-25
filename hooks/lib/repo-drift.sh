#!/usr/bin/env bash
# Shared judge for "repo drift" — the two silent states a session opens into that no
# gate enforces, but the orchestrator keeps getting burned by. Surfaced (not enforced)
# by the SessionStart doctor (bootstrap-session-doctor.sh).
#
#   (1) HEAD behind the main remote-tracking ref — the stale-checkout class
#       (incidents 2026-06-16-prod-migration-from-stale-checkout /
#        2026-06-12-shared-checkout-branch-collision in the appo-followup dogfood):
#       `git status` clean is trusted as "on latest main" and a prod op (migration /
#       deploy / 取込 / 直 push) runs from an N-commit-behind tree. status clean ≠ on
#       latest main — the divergence is invisible until something breaks.
#   (2) a linked worktree whose branch is already merged into the main ref — a sprint
#       lane that integrate(skill) should have torn down AFTER merge but didn't, so
#       worktrees accumulate. Ephemeral lane state whose termination owner was skipped
#       (cf. memory feedback_gate_signal_and_failmode: read ephemeral state by liveness,
#       and own the teardown). Leftover lanes also silently consume the WIP budget.
#
# This is VISIBILITY, not enforcement. Whether a given checkout is right for a given op
# is an irreducible judgment (ADR 0001's residue) — but the drift FACT can be shown
# (ADR 0003's doctrine: consent / judgment can't be forced, state can be surfaced). So
# nothing here exits 2; drift_report prints human-readable lines the doctor injects, and
# is SILENT when there is no drift (no advisory bloat — same bar as the adoption audit).
#
# OFFLINE & FAST: SessionStart must not block on the network, so we DO NOT fetch. We
# compare against the LOCAL remote-tracking ref. A stale tracking ref only UNDER-reports
# drift (shows fewer commits behind than reality), so the nudge is never a false alarm —
# at worst it stays quiet when a fetch would have spoken. The advice line tells the
# reader to fetch to get the authoritative count.
#
# Contract (all take the repo dir as $1 so the doctor can audit the session cwd, not the
# plugin's own dir; pure bash + git porcelain, jq-free, no network):
#   drift_main_ref <dir>              echo the remote-tracking ref to compare against
#                                     (origin/HEAD's target → origin/main → origin/master);
#                                     return 1 + no stdout if none is resolvable.
#   behind_count <dir> <ref>          echo integer = commits in <ref> not in HEAD (0 on error,
#                                     OFFLINE — never fetches; the doctor's no-network path).
#   fetched_behind_count <dir> <remote> <branch>
#                                     ONLINE twin of behind_count for the per-action gate
#                                     (block-stale-write-to-protected): does an explicit,
#                                     timeout-bounded fetch of <remote>/<branch> FIRST so the
#                                     count is authoritative, then echoes behind. Returns 0
#                                     only when the fetch succeeded; returns 1 (and the gate
#                                     must fail OPEN) when the fetch failed/timed out — see
#                                     its own header for why the two are separate authorities.
#   merged_worktree_lines <dir> <ref> echo one indented line per LINKED worktree whose branch
#                                     tip is an ancestor of <ref> (= merged), excluding the
#                                     main branch itself and detached heads.
#   drift_report <dir>                echo the full human-readable block, or nothing; return 0.

# _rd_main_branch — the local branch name a remote-tracking ref maps to (origin/main → main).
_rd_main_branch() { printf '%s' "${1#*/}"; }

# drift_main_ref — see header.
drift_main_ref() {
  local dir="$1" sym cand
  # the remote's declared default branch, if origin/HEAD is set locally
  sym=$(git -C "$dir" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null)
  if [ -n "$sym" ]; then
    printf '%s' "${sym#refs/remotes/}"
    return 0
  fi
  for cand in origin/main origin/master; do
    if git -C "$dir" rev-parse --verify --quiet "refs/remotes/$cand" >/dev/null 2>&1; then
      printf '%s' "$cand"
      return 0
    fi
  done
  return 1
}

# behind_count — see header. Always echoes a non-negative integer.
behind_count() {
  local dir="$1" ref="$2" n
  n=$(git -C "$dir" rev-list --count "HEAD..$ref" 2>/dev/null)
  case "$n" in
    '' | *[!0-9]*) printf '0' ;;
    *) printf '%s' "$n" ;;
  esac
}

# fetched_behind_count — ONLINE staleness, the single authority the per-action gate
# (block-stale-write-to-protected.sh) shares with this lib so the online gate and the
# offline doctor cannot drift on what "behind" means.
#
# Why a SECOND function and not a flag on behind_count: behind_count is the SessionStart
# doctor's path and MUST stay no-network (the header's OFFLINE & FAST contract — session
# start must never block on a fetch). The gate, by contrast, is about to allow an
# IRREVERSIBLE trunk push and needs the AUTHORITATIVE count, so it MUST fetch. Folding a
# "maybe fetch" branch into behind_count would put a network call on the doctor's hot path
# by accident the first time someone passes the wrong arg. Keeping them as two named
# functions makes the network/no-network choice explicit at every call site (same reason
# is_protected takes its file path explicitly instead of a hidden global).
#
# The fetch is EXPLICIT-refspec and timeout-bounded:
#   git -C <dir> fetch --quiet <remote> +refs/heads/<branch>:refs/remotes/<remote>/<branch>
# - explicit refspec (not a bare `git fetch`) so we update EXACTLY the one tracking ref we
#   are about to compare against and nothing else — a misconfigured remote.fetch or a huge
#   remote can't turn this into an unbounded sync, and the leading + force-updates the
#   tracking ref so a rewound/rebased remote tip still yields a correct count.
# - `timeout` if present (absence tolerated — older/minimal boxes lack coreutils timeout):
#   a hung auth prompt or dead host must not wedge the gate. A timeout kill counts as a
#   FETCH FAILURE (return 1), so the gate fails OPEN — network unavailability must NEVER
#   block work (no-grounds = fail-OPEN; non-target/offline repos are never disturbed).
#
# Return contract (the fail-mode the gate keys on):
#   fetch SUCCEEDED -> echo behind (>=0), return 0  (only here may the gate block, iff >0)
#   fetch FAILED/timed out -> echo nothing, return 1 (gate fails OPEN, announced)
# behind itself is `git rev-list --count HEAD..<remote>/<branch>` after the fetch.
fetched_behind_count() {
  local dir="$1" remote="$2" branch="$3" n
  local refspec="+refs/heads/$branch:refs/remotes/$remote/$branch"
  if command -v timeout >/dev/null 2>&1; then
    # 10s wall clock: long enough for a real LAN/HTTPS fetch, short enough that a dead
    # host or stuck credential prompt can't wedge a PreToolUse gate. timeout's own exit
    # (124 on kill, 126/127 if it can't run) all fall into the non-zero = fail-OPEN arm.
    timeout 10 git -C "$dir" fetch --quiet "$remote" "$refspec" >/dev/null 2>&1 || return 1
  else
    git -C "$dir" fetch --quiet "$remote" "$refspec" >/dev/null 2>&1 || return 1
  fi
  n=$(git -C "$dir" rev-list --count "HEAD..refs/remotes/$remote/$branch" 2>/dev/null)
  case "$n" in
    '' | *[!0-9]*) printf '0' ;;
    *) printf '%s' "$n" ;;
  esac
  return 0
}

# _rd_emit_merged — print the line for one worktree record if it is a merged lane.
_rd_emit_merged() {
  local dir="$1" ref="$2" main_branch="$3" wt_path="$4" wt_branch="$5"
  [ -n "$wt_branch" ] || return 0                  # detached head — not a lane to flag
  [ "$wt_branch" = "$main_branch" ] && return 0     # the main worktree itself, never a leftover
  if git -C "$dir" merge-base --is-ancestor "refs/heads/$wt_branch" "refs/remotes/$ref" 2>/dev/null; then
    printf '  %s  (branch %s — %s に merge 済み)\n' "$wt_path" "$wt_branch" "$ref"
  fi
}

# merged_worktree_lines — see header. Parses `git worktree list --porcelain` records
# (blank-line separated; each has a `worktree <path>` and either `branch <ref>` or
# `detached`).
merged_worktree_lines() {
  local dir="$1" ref="$2" main_branch line wt_path="" wt_branch=""
  main_branch=$(_rd_main_branch "$ref")
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "worktree "*) wt_path="${line#worktree }" ;;
      "branch "*)
        wt_branch="${line#branch }"
        wt_branch="${wt_branch#refs/heads/}"
        ;;
      "")
        _rd_emit_merged "$dir" "$ref" "$main_branch" "$wt_path" "$wt_branch"
        wt_path=""; wt_branch=""
        ;;
    esac
  done < <(git -C "$dir" worktree list --porcelain 2>/dev/null)
  # guard the final record in case porcelain output is not blank-terminated
  [ -n "$wt_path" ] && _rd_emit_merged "$dir" "$ref" "$main_branch" "$wt_path" "$wt_branch"
}

# drift_report — see header. Composes the two audits; silent when neither fires.
drift_report() {
  local dir="$1" ref behind cur wts out=""
  git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  ref=$(drift_main_ref "$dir") || return 0

  behind=$(behind_count "$dir" "$ref")
  if [ "$behind" -gt 0 ] 2>/dev/null; then
    cur=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
    out="${out}HEAD (${cur:-?}) は ${ref} より ${behind} commit 遅れ — 本番に副作用を持つ操作 (migration / deploy / 取込 / 直 push) の前に追従を確認:
  git fetch && git rev-list --left-right --count HEAD...${ref}
  status が clean でも「最新 main にいる」ことは保証されない。遅れたまま走らせると古いロジックで本番を汚す
  (incident 2026-06-16-prod-migration-from-stale-checkout)。
"
  fi

  wts=$(merged_worktree_lines "$dir" "$ref")
  if [ -n "$wts" ]; then
    out="${out}merge 済みなのに残っている worktree (lane の撤去漏れ — integrate skill は merge の後に worktree を撤去する):
${wts}  撤去: git worktree remove <path> (未コミットが無いか確認してから)。残すと並列 lane が WIP 上限を無駄に食う。
"
  fi

  [ -n "$out" ] && printf 'リポジトリ drift (advisory — 強制ではない。判断はあなたが下す):\n%s' "$out"
  return 0
}
