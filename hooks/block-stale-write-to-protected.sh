#!/usr/bin/env bash
# Hook — PreToolUse on Bash for a `git push` whose DESTINATION is the TRUNK.
# Blocks pushing to the trunk from a STALE checkout — a tree N commits behind the remote
# trunk — because two real incidents came from exactly that:
#   - 2026-06-16-prod-migration-from-stale-checkout: a prod migration ran from a 24-commit-
#     behind tree; `git status` was clean so it was trusted as "on latest main" and old
#     logic touched production.
#   - 2026-06-25-stale-staged-commit (rebase-drops-deploy): a push to the trunk from a stale
#     main silently dropped a commit when the remote had moved on.
# status clean ≠ on latest trunk. The divergence is invisible until something breaks, so we
# make the otherwise-allowed trunk push a precondition: it must be FRESH (behind == 0).
#
# ORTHOGONAL to block-push-to-protected.sh — NOT a duplicate (see ADR 0009):
#   - block-push-to-protected enforces PR-FLOW via opt-in .bootstrap-protected: it blocks a
#     DIRECT push to a declared-protected branch OUTRIGHT (freshness irrelevant).
#   - THIS gate enforces FRESHNESS of an otherwise-ALLOWED trunk push, keyed on the trunk
#     that lib/repo-drift.sh's drift_main_ref resolves (origin/main -> main, origin/master
#     -> master), NOT .bootstrap-protected. Keying on .bootstrap-protected would (a) duplicate
#     the PR-flow gate AND (b) fail to fire on repos that legitimately push the trunk directly
#     and have no .bootstrap-protected (e.g. this plugin's own release flow).
# ORDERING: this runs AFTER block-push-to-protected. On a repo that DOES protect the trunk,
# the direct push is already blocked there; this gate is the net for the direct-trunk-push
# case the other one intentionally allows (no .bootstrap-protected).
#
# Signal = the ACTION (a git push whose destination resolves to the trunk branch) + a
# physical staleness fact (fetched behind count > 0), NOT a string proxy. The deliberately
# NON-gated sibling is an arbitrary prod script (e.g. `tsx migrate.ts`, a deploy command):
# it has NO deterministic trace tying it to "this checkout is stale", so forcing it here
# would be an irreducible judgment. That class stays with the SessionStart drift advisory
# (bootstrap-session-doctor.sh + lib/repo-drift.sh drift_report), which surfaces the behind
# count at session open — see ADR 0009.
#
# Fail-mode (deliberate):
#   parse-impossible          -> fail-CLOSED (exit 2). A BLOCKING gate that can't read its
#                                input must not wave the push through.
#   fail-OPEN (exit 0), announced via stderr only when it would otherwise have blocked, on:
#     not a git push / no git or not a work tree / trunk ref unresolvable / destination is
#     not the trunk / fetch fails or times out (offline, no remote, auth fail) / behind == 0.
#     Rationale: no-grounds = fail-OPEN so non-target and offline repos are NEVER disturbed;
#     network unavailability must NEVER block work.
#   BLOCK (exit 2) fires ONLY when: trunk push + fetch SUCCEEDS + behind > 0.
#
# bypass: 例外的に stale のまま trunk へ push する必要があるなら /permissions で本 hook を一時 deny。
# Pure bash, jq-free.

set -u

INPUT=$(cat)
# shellcheck source=lib/parse-command.sh
. "$(dirname "$0")/lib/parse-command.sh"
# shellcheck source=lib/protected-branch.sh
# Single authority for `git push` detection + refspec-destination enumeration across
# compound commands and path-prefixed git (cmd_has_git_push / push_destination_branches).
. "$(dirname "$0")/lib/protected-branch.sh"
# shellcheck source=lib/repo-drift.sh
# Single authority on staleness (drift_main_ref resolves the trunk; fetched_behind_count is
# the ONLINE behind count) so this gate and the offline SessionStart doctor cannot drift.
. "$(dirname "$0")/lib/repo-drift.sh"

if ! CMD="$(printf '%s' "$INPUT" | parse_command)"; then
  echo "project-bootstrap: could not parse the tool command from hook input — blocking to fail safe (fail-closed). If this is a false positive, disable this hook via /permissions." >&2
  exit 2
fi

[ -z "$CMD" ] && exit 0

# git push でなければ素通し (path-prefixed git も検出する: cmd_has_git_push)。
cmd_has_git_push "$CMD" || exit 0

# git / work-tree が無ければ判断不能 → fail-open。
command -v git >/dev/null 2>&1 || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# 比較対象の trunk を repo-drift の single authority で解決する (origin/main -> main 等)。
# 解決できなければ「trunk push かどうか」を判定する根拠が無い → fail-open。
TRUNK_REF=$(drift_main_ref ".") || exit 0     # e.g. origin/main
TRUNK_REMOTE="${TRUNK_REF%%/*}"               # origin
TRUNK_BRANCH="${TRUNK_REF#*/}"                # main
# 解決結果が <remote>/<branch> の形でなければ判断不能 → fail-open。
[ -n "$TRUNK_REMOTE" ] && [ -n "$TRUNK_BRANCH" ] && [ "$TRUNK_REMOTE" != "$TRUNK_REF" ] || exit 0

# この push の destination が trunk branch に一致するか判定する。
# push_destination_branches は refspec destination を全 segment 分 列挙する (compound command
# / path-prefixed git / src:dst / +force / refs/heads/ prefix を正規化済み)。1 つでも trunk
# branch に一致すれば「trunk への push」と判定する (first trunk hit)。
TARGETS_TRUNK=0
HAS_REFSPEC=0
while IFS= read -r dst; do
  [ -z "$dst" ] && continue
  HAS_REFSPEC=1
  if [ "$dst" = "$TRUNK_BRANCH" ]; then
    TARGETS_TRUNK=1
    break
  fi
done <<EOF
$(push_destination_branches "$CMD")
EOF

# --all / --branches / --mirror は refspec を列挙しない (= destination は「全 local branch」)。
# local trunk branch が存在するなら trunk もその集合に含まれる → trunk push と判定する
# (fail-closed: 破壊 scope が列挙不能な push を current-branch 判定に落とさない。ADR 0019)。
if [ "$TARGETS_TRUNK" -eq 0 ] && push_pushes_all_branches "$CMD"; then
  git rev-parse --verify --quiet "refs/heads/$TRUNK_BRANCH" >/dev/null 2>&1 && TARGETS_TRUNK=1
fi

# refspec が無い push は暗黙に現在 branch を push する → 現在 branch が trunk なら trunk push。
if [ "$TARGETS_TRUNK" -eq 0 ] && [ "$HAS_REFSPEC" -eq 0 ] && ! push_pushes_all_branches "$CMD"; then
  CUR=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  [ "$CUR" = "$TRUNK_BRANCH" ] && TARGETS_TRUNK=1
fi

# trunk への push でなければ何も強制しない → fail-open (= feature branch push は一切妨げない)。
[ "$TARGETS_TRUNK" -eq 1 ] || exit 0

# ここまでで「trunk への push」と確定。authoritative な behind 数を取りに行く。
# fetched_behind_count は明示 refspec + timeout 付き fetch を先に行い、成功時のみ behind を
# echo して return 0、fetch 失敗 (offline / no remote / auth fail / timeout) なら return 1。
# fetch 失敗は work を止めない (network unavailability で block しない) → fail-open。
BEHIND=$(fetched_behind_count "." "$TRUNK_REMOTE" "$TRUNK_BRANCH") || exit 0

# behind == 0 (= 最新の trunk にいる) なら fresh なので素通し。
[ "$BEHIND" -gt 0 ] 2>/dev/null || exit 0

# trunk push + fetch 成功 + behind > 0 — ここでのみ block する。
cat >&2 <<EOF
project-bootstrap: blocking a push to the trunk from a STALE checkout — HEAD is ${BEHIND} commit(s) behind ${TRUNK_REF}.

push 先 '${TRUNK_BRANCH}' は trunk だが、この checkout は remote trunk より ${BEHIND} commit 遅れている。
status が clean でも「最新 ${TRUNK_BRANCH} にいる」ことは保証されない。遅れたまま trunk へ push すると:
  - 古いロジックで本番を汚す (incident 2026-06-16-prod-migration-from-stale-checkout)
  - remote が進んだ分を取りこぼし commit を落とす (incident 2026-06-25-stale-staged-commit)

対処 (push 前に trunk へ追従する):
  git fetch ${TRUNK_REMOTE} ${TRUNK_BRANCH}
  git rebase ${TRUNK_REF}      # または: git pull --rebase ${TRUNK_REMOTE} ${TRUNK_BRANCH}
  # 追従して behind が 0 になってから push し直す

意図的に stale のまま trunk へ push する必要があるなら、/permissions で本 hook を一時 deny にする。
EOF
exit 2
