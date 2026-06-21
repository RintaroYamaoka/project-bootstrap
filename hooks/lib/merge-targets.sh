#!/usr/bin/env bash
# Shared merge-target extraction for the two integration gates
# (block-unreviewed-merge.sh, block-merge-if-verification-unclosed.sh).
#
# Single authority so the two gates cannot drift on what counts as a merge target —
# drift in a gate signal IS the silent-bypass class this repo treats as a first-class
# bug (same policy as lib/board-liveness.sh, lib/source-face.sh, lib/parse-command.sh).
#
# Why this exists (the bug it fixes): both gates used to extract the merge target with
#   ARGS=$(printf '%s' "$CMD" | sed -E 's/^.*git[[:space:]]+merge//')
# `.*` is greedy, so in a compound command `git merge A && git merge B` it stripped up
# to the LAST `git merge` and only ever inspected B — A was merged past the gate with
# zero enforcement. And the detector keyed on a bare `git merge` token, so
# `/usr/bin/git merge` slipped by unseen. Both are the exact "string proxy for an
# action" weakness the doctrine condemns for sprint vocabulary (move ②). This walks
# EVERY git-merge segment of a compound command and accepts path-prefixed git.
#
# Known limit (documented, not silent): a separator metacharacter that appears INSIDE a
# quoted merge message (e.g. git merge -m "a && b" feat/x) is indistinguishable from a
# real separator without a full shell parser, so that one input can miss its branch
# (fail-open for that case only). The commit-time arch/test gates and CI remain as nets.
# Pure bash, jq-free.

# cmd_has_git_merge <command> — return 0 if the command invokes `git merge`.
# Matches bare `git` and path-prefixed forms (/usr/bin/git, ./git) by allowing `/`
# immediately before `git`; does not match `mygit`/`legit` (preceding char is a letter).
cmd_has_git_merge() {
  printf '%s' "$1" | grep -qE '(^|[[:space:]&|;()`]|/)git[[:space:]]+merge([[:space:]]|$)'
}

# merge_target_branches <command> — print every positional argument given to a
# `git merge` in the command, one per line, across all segments of a compound command
# (&&, ||, ;, |, &). Flags and the values of argument-taking flags (-m/-F/-s/-S/-X ...)
# are skipped so a commit message is never mistaken for a branch. The caller decides
# which printed tokens are lane branches (is_lane_branch) — this only enumerates targets.
merge_target_branches() {
  local cmd="$1" tok skip_next=0 in_merge=0 prev="" norm noglob=0
  # Pad shell separators so they tokenize as standalone words even when written without
  # surrounding spaces (git merge a;git merge b). The separators are kept (not deleted)
  # so they reset in_merge and stop a following non-merge command's words from being
  # read as targets (git merge a && echo feat/x must NOT yield feat/x).
  norm="$(printf '%s' "$cmd" | sed -E 's/(\&\&|\|\||;|\||\&)/ & /g')"
  # noglob during word-splitting so a branch/arg containing * or ? is not expanded
  # against the filesystem (which could drop or mangle a target = fail-open).
  case $- in *f*) ;; *) noglob=1; set -f ;; esac
  # shellcheck disable=SC2086
  set -- $norm
  [ "$noglob" = 1 ] && set +f
  while [ $# -gt 0 ]; do
    tok="$1"; shift
    case "$tok" in
      '&&'|'||'|';'|'|'|'&') in_merge=0; skip_next=0; prev="$tok"; continue ;;
    esac
    if [ "$tok" = merge ]; then
      case "$prev" in
        git|*/git) in_merge=1; skip_next=0; prev="$tok"; continue ;;
      esac
    fi
    if [ "$in_merge" = 1 ]; then
      if [ "$skip_next" = 1 ]; then skip_next=0; prev="$tok"; continue; fi
      case "$tok" in
        -m|--message|-F|--file|--into-name|-S|--gpg-sign|--strategy|-s|--strategy-option|-X)
          skip_next=1; prev="$tok"; continue ;;
        -*) prev="$tok"; continue ;;
      esac
      printf '%s\n' "$tok"
    fi
    prev="$tok"
  done
}
