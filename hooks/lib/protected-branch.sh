#!/usr/bin/env bash
# Shared push-destination extraction + protected-branch authority for the push gates
# (block-push-to-protected.sh, block-stale-write-to-protected.sh).
#
# Single authority so the gates and any future caller cannot drift on what counts as a
# push destination or as a protected branch — drift in a gate signal IS the silent-bypass
# class this repo treats as a first-class bug (same policy as lib/merge-targets.sh,
# lib/board-liveness.sh, lib/source-face.sh, lib/parse-command.sh).
#
# Detection + segment walking + git-global-option handling are delegated to
# lib/git-invocation.sh (ADR 0019): the 2026-07-10 audit reproduced FOUR live bypasses
# where a global option between `git` and `push` (git -C /repo push …, git -c k=v push …,
# git --git-dir=.git push …, git -P push …) made both the detector regex AND this file's
# old tokenizer (which armed only when the token before `push` was `git`) miss the push
# entirely — the protected-branch gate exited 0 on the very command it exists to block.
# This lib now only owns the PUSH-SPECIFIC shape: first positional = remote, remaining
# positionals = refspecs whose DESTINATION is the branch the gate must judge, plus the
# --all/--mirror/--branches "destination set = every local branch" predicate.
#
# Known limit (documented, not silent): a separator metacharacter INSIDE a quoted
# argument can mis-split (see git-invocation.sh header). The commit-time gates and CI
# remain as nets. Pure bash, jq-free.

# Resolve the shared walker relative to this lib (works when sourced from any cwd).
# shellcheck source=git-invocation.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/git-invocation.sh"

# cmd_has_git_push <command> — return 0 if the command invokes `git push`.
# Single authority = cmd_invokes_git_subcommand: path-prefixed git (/usr/bin/git, ./git)
# and git global options (git -C /repo push …) are handled there; `mygit`/`legit` never
# match (the head token must be `git` or `*/git`).
cmd_has_git_push() {
  cmd_invokes_git_subcommand "$1" push
}

# is_protected <branch> <protected-file> — return 0 if <branch> matches any glob declared
# in <protected-file>. One declaration per line; surrounding whitespace is trimmed, blank
# lines and `#` comment lines are ignored, and the match is a shell glob via [[ == ]].
# The gate and the lib share one authority on what is protected (the file path is passed
# explicitly rather than read from a hidden global, so a caller's intent is visible at
# the call site).
is_protected() {
  local b="$1" file="$2" pat
  while IFS= read -r pat || [ -n "$pat" ]; do
    pat="${pat#"${pat%%[![:space:]]*}"}"; pat="${pat%"${pat##*[![:space:]]}"}"
    [ -z "$pat" ] && continue
    case "$pat" in \#*) continue ;; esac
    # shellcheck disable=SC2053
    [[ "$b" == $pat ]] && return 0
  done < "$file"
  return 1
}

# push_destination_branches <command> — print the DESTINATION branch of every refspec
# given to a `git push` in the command, one per line, across all segments of a compound
# command (&&, ||, ;, |, &). Segment walking + global-option skipping come from
# git_subcommand_arglines; this walks each push argline. The first positional after the
# push token is the remote (not a branch) and is never emitted; subsequent positionals
# are refspecs. Flags and the values of argument-taking push flags (--repo, -o/
# --push-option, --receive-pack, --exec) are skipped so a flag value is never mistaken
# for a branch (the `--flag=value` inline form carries its own value and needs no
# separate skip). For each refspec the printed branch is its destination: `src:dst` ->
# dst, then a leading `+` (force) and a `refs/heads/` prefix are stripped. A `git push`
# with NO refspec emits nothing — the caller handles the implicit-current-branch case,
# and MUST also consult push_pushes_all_branches (an --all/--mirror push enumerates
# nothing here by design). The caller decides which printed branches are protected
# (is_protected) — this only enumerates destinations.
push_destination_branches() {
  local cmd="$1" line tok skip_next positional dst noglob=0
  # noglob during word-splitting so a refspec containing * or ? is not expanded against
  # the filesystem (which could drop or mangle a destination = fail-open).
  case $- in *f*) ;; *) noglob=1; set -f ;; esac
  while IFS= read -r line; do
    skip_next=0; positional=0
    # shellcheck disable=SC2086
    set -- $line
    while [ $# -gt 0 ]; do
      tok="$1"; shift
      if [ "$skip_next" = 1 ]; then skip_next=0; continue; fi
      case "$tok" in
        # Flags whose VALUE is a separate following token — skip that value so it is
        # never read as a remote or a branch.
        --repo|-o|--push-option|--receive-pack|--exec)
          skip_next=1; continue ;;
        -*) continue ;;
      esac
      # First positional after the push token is the remote, not a branch.
      positional=$((positional + 1))
      [ "$positional" -eq 1 ] && continue
      # Refspec: destination is the dst of src:dst (else the token itself); then strip a
      # leading + (force) and a refs/heads/ prefix to normalize to the bare branch name.
      case "$tok" in
        *:*) dst="${tok##*:}" ;;
        *)   dst="$tok" ;;
      esac
      dst="${dst#+}"
      dst="${dst#refs/heads/}"
      printf '%s\n' "$dst"
    done
  done < <(git_subcommand_arglines "$cmd" push)
  [ "$noglob" = 1 ] && set +f
  return 0
}

# push_pushes_all_branches <command> — return 0 if ANY `git push` segment carries
# --all / --branches (push every local branch) or --mirror (push/prune ALL refs).
# For these forms the refspec enumeration above yields NOTHING, and the old gate then
# fell back to judging only the CURRENT branch — so `git push --all origin` from a
# feature branch pushed a protected main straight past the gate (2026-07-10 audit,
# reproduced live). The destination set of such a push is "every local branch", which
# the command string cannot enumerate — the CALLER must expand it (git for-each-ref)
# and judge each branch: fail-CLOSED when the blast scope is unenumerable (ADR 0019).
# The values of argument-taking push flags are skipped so `-o --all` is not misread.
push_pushes_all_branches() {
  local cmd="$1" line tok skip_next noglob=0
  case $- in *f*) ;; *) noglob=1; set -f ;; esac
  while IFS= read -r line; do
    skip_next=0
    # shellcheck disable=SC2086
    set -- $line
    while [ $# -gt 0 ]; do
      tok="$1"; shift
      if [ "$skip_next" = 1 ]; then skip_next=0; continue; fi
      case "$tok" in
        --repo|-o|--push-option|--receive-pack|--exec) skip_next=1 ;;
        --all|--branches|--mirror)
          [ "$noglob" = 1 ] && set +f
          return 0 ;;
      esac
    done
  done < <(git_subcommand_arglines "$cmd" push)
  [ "$noglob" = 1 ] && set +f
  return 1
}
