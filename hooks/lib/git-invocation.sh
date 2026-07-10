#!/usr/bin/env bash
# Shared, single-authority walker for "does this command invoke `git <subcommand>`?"
# (ADR 0019 — docs/decisions/0019-git-invocation-detection-single-authority.md)
#
# Why this exists (the live bug class, all reproduced in the 2026-07-10 audit): every
# Bash gate answered the question with its own regex —
#   (^|[[:space:]&|;()`]+)git[[:space:]]+commit($|[[:space:]])
# That string proxy requires the subcommand IMMEDIATELY after the word `git`, so it
# missed ALL of these, and the blocking gates fail-OPENed on the very commands they
# exist to block (protected push / test / lint / arch / lane / cross-wip):
#   - git GLOBAL OPTIONS between git and the subcommand:
#       git -C /repo push origin main      (value in the NEXT token)
#       git -c k=v commit -m x
#       git --git-dir=.git push …          (inline value)
#       git -P push … / git --no-pager …   (flag-only)
#   - path-prefixed git on the commit-side gates: /usr/bin/git commit, ./git commit
#     (the push/merge libs already allowed `/`; the commit gates never got the fix).
# Patching the regex per new option is whack-a-mole. This lib tokenizes instead:
# pad shell separators -> word-split under noglob -> find a `git`/`*/git` head ->
# skip git global options (value-takers swallow the NEXT token; any other `-…` token
# before the subcommand is a flag-only global) -> the FIRST non-option token is THE
# subcommand of that invocation. Every segment of a compound command is walked.
#
# Fail-direction of the design: an UNKNOWN `-…` token between git and the subcommand
# is treated as a flag-only global option (git itself would error on it anyway), so
# ambiguity biases toward DETECTION — for blocking gates that is the safe (closed)
# side, never the silent-bypass side.
#
# Known limits (documented, not silent — same as merge-targets.sh/protected-branch.sh;
# both are irreducible without a full shell parser):
#   - quoted SEPARATOR / a `git <sub>` sequence inside a quoted argument: mis-splits
#     toward OVER-detect (a quoted "git commit" in a message arms a gate = fail-closed
#     noise on a blocking gate).
#   - quote/escape on the GIT-HEAD or SUBCOMMAND token itself, a glued redirection, or
#     a nested-shell launcher: `git 'push' …` / `"git" push …` / `\git push …` /
#     `git pu\sh …` / `git push>/dev/null …` / `sh -c "git push …"` tokenize to words
#     this walker does not de-quote/unwrap, so they UNDER-detect (silent pass). This is
#     the same hole the old regexes had (no regression); the commit-time gates and the
#     server-side CI/branch-protection layer (ADR 0012) remain as nets.
# Pure bash + sed/grep, jq-free.

# _git_gopt_takes_value <tok> — return 0 if <tok> is a git GLOBAL option whose value
# is the NEXT token (git accepts the space-separated form for these). Inline `=`
# forms (--git-dir=…) carry their value in the same token and fall to the generic
# flag-only arm in the walker. --exec-path/--html-path & friends never take a
# separate-token value, so they are deliberately NOT listed.
_git_gopt_takes_value() {
  case "$1" in
    -C|-c|--git-dir|--work-tree|--namespace|--config-env|--attr-source) return 0 ;;
    *) return 1 ;;
  esac
}

# git_subcommand_arglines <cmd> <sub> — for EVERY segment of a (possibly compound)
# command that invokes `git <sub>`, print ONE line: the segment's remaining tokens
# joined by single spaces. An argument-less invocation prints an EMPTY line (the
# segment still counts). No matching segment prints nothing at all — callers can use
# `| grep -q ''` as the existence test (cmd_invokes_git_subcommand does exactly that).
# Git global options are consumed BEFORE the subcommand and never appear in a line.
git_subcommand_arglines() {
  local cmd="$1" sub="$2" tok norm noglob=0 in_git=0 skip_next=0 collecting=0 acc=""
  # Pad shell separators (incl. subshell parens and backticks) so they tokenize as
  # standalone words even when written without surrounding spaces (git stash;git stash).
  norm="$(printf '%s' "$cmd" | sed -E 's/(\&\&|\|\||;|\||\&|\(|\)|`)/ & /g')"
  # noglob during word-splitting so a token containing * or ? is not expanded against
  # the filesystem (which could drop or mangle a token = fail-open).
  case $- in *f*) ;; *) noglob=1; set -f ;; esac
  # shellcheck disable=SC2086
  set -- $norm
  while [ $# -gt 0 ]; do
    tok="$1"; shift
    case "$tok" in
      '&&'|'||'|';'|'|'|'&'|'('|')'|'`')
        [ "$collecting" = 1 ] && printf '%s\n' "$acc"
        in_git=0; skip_next=0; collecting=0; acc=""
        continue ;;
    esac
    if [ "$collecting" = 1 ]; then
      if [ -z "$acc" ]; then acc="$tok"; else acc="$acc $tok"; fi
      continue
    fi
    if [ "$in_git" = 1 ]; then
      if [ "$skip_next" = 1 ]; then skip_next=0; continue; fi
      case "$tok" in
        -*)
          # a git GLOBAL option before the subcommand; value-takers swallow the next token
          _git_gopt_takes_value "$tok" && skip_next=1
          continue ;;
      esac
      # first non-option token after `git` = THE subcommand of this invocation
      if [ "$tok" = "$sub" ]; then
        collecting=1; acc=""
      else
        in_git=0
      fi
      continue
    fi
    case "$tok" in
      git|*/git) in_git=1; skip_next=0 ;;
    esac
  done
  [ "$collecting" = 1 ] && printf '%s\n' "$acc"
  [ "$noglob" = 1 ] && set +f
  return 0
}

# cmd_invokes_git_subcommand <cmd> <sub> — return 0 if ANY segment of the command
# invokes `git <sub>` (path-prefixed git and git global options included).
cmd_invokes_git_subcommand() {
  git_subcommand_arglines "$1" "$2" | grep -q ''
}
