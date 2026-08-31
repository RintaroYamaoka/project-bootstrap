#!/usr/bin/env bash
# Shared merge-target extraction for the two integration gates
# (block-unreviewed-merge.sh, block-merge-if-verification-unclosed.sh).
#
# Single authority so the two gates cannot drift on what counts as a merge target —
# drift in a gate signal IS the silent-bypass class this repo treats as a first-class
# bug (same policy as lib/board-liveness.sh, lib/source-face.sh, lib/parse-command.sh).
#
# History of the bug class this kills: both gates once used a greedy
# `sed 's/^.*git merge//'` (only the LAST merge of a compound command was inspected)
# and a bare-`git merge` token detector (`/usr/bin/git merge` was invisible). The first
# rewrite fixed those two but armed only when the token BEFORE `merge` was `git`, so a
# git GLOBAL option (`git -C /repo merge feat/x`, `git -c k=v merge …`) still slipped
# past unseen — the same live bypass class the 2026-07-10 audit reproduced on the push
# side. Detection + segment walking + global-option skipping now come from the single
# authority lib/git-invocation.sh (ADR 0019); this lib only owns the MERGE-SPECIFIC
# shape (which argline tokens are targets vs flags/flag-values).
#
# Known limits (documented, not silent — see git-invocation.sh header for the full
# statement): a separator INSIDE a quoted merge message (e.g. git merge -m "a && b"
# feat/x) mis-splits toward OVER-detect / a missed branch, but a quote/escape on the
# git-head or subcommand token itself (`"git" merge`, `git 'merge'`) or a nested
# `sh -c "git merge …"` UNDER-detects (silent pass) — irreducible without a full shell
# parser. The commit-time arch/test gates and the server-side layer (branch protection
# + CI, ADR 0012) remain as nets. Pure bash, jq-free.

# Resolve the shared walker relative to this lib (works when sourced from any cwd).
# shellcheck source=git-invocation.sh
# Include guard — dispatcher が 1 プロセスに複数 gate を source するときの再読込抑止。
[ -n "${_BOOTSTRAP_LIB_MERGE_TARGETS:-}" ] && return 0
_BOOTSTRAP_LIB_MERGE_TARGETS=1

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/git-invocation.sh"

# cmd_has_git_merge <command> — return 0 if the command invokes `git merge`.
# Single authority = cmd_invokes_git_subcommand: path-prefixed git and git global
# options are handled there; `mygit`/`legit` never match.
cmd_has_git_merge() {
  cmd_invokes_git_subcommand "$1" merge
}

# merge_target_branches <command> — print every positional argument given to a
# `git merge` in the command, one per line, across all segments of a compound command
# (&&, ||, ;, |, &). Flags and the values of argument-taking flags (-m/-F/-s/-S/-X ...)
# are skipped so a commit message is never mistaken for a branch. The caller decides
# which printed tokens are lane branches (is_lane_branch) — this only enumerates targets.
merge_target_branches() {
  local cmd="$1" line tok skip_next noglob=0
  # noglob during word-splitting so a branch/arg containing * or ? is not expanded
  # against the filesystem (which could drop or mangle a target = fail-open).
  case $- in *f*) ;; *) noglob=1; set -f ;; esac
  while IFS= read -r line; do
    skip_next=0
    # shellcheck disable=SC2086
    set -- $line
    while [ $# -gt 0 ]; do
      tok="$1"; shift
      if [ "$skip_next" = 1 ]; then skip_next=0; continue; fi
      case "$tok" in
        -m|--message|-F|--file|--into-name|-S|--gpg-sign|--strategy|-s|--strategy-option|-X)
          skip_next=1; continue ;;
        -*) continue ;;
      esac
      printf '%s\n' "$tok"
    done
  done < <(git_subcommand_arglines "$cmd" merge)
  [ "$noglob" = 1 ] && set +f
  return 0
}
