#!/usr/bin/env bash
# Shared push-destination extraction + protected-branch authority for the push gate
# (block-push-to-protected.sh).
#
# Single authority so the gate and any future caller cannot drift on what counts as a
# push destination or as a protected branch — drift in a gate signal IS the silent-bypass
# class this repo treats as a first-class bug (same policy as lib/merge-targets.sh,
# lib/board-liveness.sh, lib/source-face.sh, lib/parse-command.sh). This is modeled
# EXACTLY on lib/merge-targets.sh: the push refspec walk is the merge-target walk with
# the push-specific shape (first positional = remote, rest = refspecs whose DESTINATION
# is the branch the gate must judge).
#
# Why this exists (the two LIVE bugs it fixes): the gate used
#   echo "$CMD" | grep -qE '(^|[[:space:]&|;()`]+)git[[:space:]]+push'  # detector
#   ARGS=$(printf '%s' "$CMD" | sed -E 's/^.*git[[:space:]]+push//')      # arg extraction
#   1. The detector had NO leading `/` allowance, so `/usr/bin/git push` and `./git push`
#      were MISSED entirely — a path-prefixed git pushed straight past the gate unseen.
#   2. `.*` is greedy, so in a compound command `git push origin main && git push origin
#      feat/x` the sed stripped up to the LAST `git push` and only ever inspected the
#      feat/x push — the protected push to `main` went through with ZERO enforcement. It
#      also walked only ONE segment. Both are the exact "string proxy for an action"
#      weakness the doctrine condemns (move ②). This walks EVERY git-push segment of a
#      compound command and accepts path-prefixed git, mirroring merge-targets.sh.
#
# Known limit (documented, not silent): a separator metacharacter that appears INSIDE a
# quoted argument (e.g. git push -o "a && b" origin main) is indistinguishable from a
# real separator without a full shell parser, so that one input can mis-split (fail-open
# for that case only). The commit-time arch/test gates and CI remain as nets.
# Pure bash, jq-free.

# cmd_has_git_push <command> — return 0 if the command invokes `git push`.
# Matches bare `git` and path-prefixed forms (/usr/bin/git, ./git) by allowing `/`
# immediately before `git`; does not match `mygit`/`legit` (preceding char is a letter).
cmd_has_git_push() {
  printf '%s' "$1" | grep -qE '(^|[[:space:]&|;()`]|/)git[[:space:]]+push([[:space:]]|$)'
}

# is_protected <branch> <protected-file> — return 0 if <branch> matches any glob declared
# in <protected-file>. One declaration per line; surrounding whitespace is trimmed, blank
# lines and `#` comment lines are ignored, and the match is a shell glob via [[ == ]].
# Moved here verbatim from block-push-to-protected.sh so the gate and the lib share one
# authority on what is protected (the file path is passed explicitly rather than read from
# a hidden global, so a caller's intent is visible at the call site).
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
# command (&&, ||, ;, |, &). The first positional after a push token is the remote (not a
# branch) and is never emitted; subsequent positionals are refspecs. Flags and the values
# of argument-taking push flags (--repo, -o/--push-option, --receive-pack, --exec) are
# skipped so a flag value is never mistaken for a branch (the `--flag=value` inline form
# carries its own value and needs no separate skip). For each refspec the printed branch
# is its destination: `src:dst` -> dst, then a leading `+` (force) and a `refs/heads/`
# prefix are stripped. A `git push` with NO refspec emits nothing — the caller handles the
# implicit-current-branch case. The caller decides which printed branches are protected
# (is_protected) — this only enumerates destinations.
push_destination_branches() {
  local cmd="$1" tok skip_next=0 in_push=0 positional=0 prev="" dst norm noglob=0
  # Pad shell separators so they tokenize as standalone words even when written without
  # surrounding spaces (git push origin main;git push origin feat/x). The separators are
  # kept (not deleted) so they reset in_push and stop a following non-push command's words
  # from being read as destinations (git push origin main && echo feat/x must NOT yield
  # feat/x).
  norm="$(printf '%s' "$cmd" | sed -E 's/(\&\&|\|\||;|\||\&)/ & /g')"
  # noglob during word-splitting so a refspec containing * or ? is not expanded against
  # the filesystem (which could drop or mangle a destination = fail-open).
  case $- in *f*) ;; *) noglob=1; set -f ;; esac
  # shellcheck disable=SC2086
  set -- $norm
  [ "$noglob" = 1 ] && set +f
  while [ $# -gt 0 ]; do
    tok="$1"; shift
    case "$tok" in
      '&&'|'||'|';'|'|'|'&') in_push=0; skip_next=0; positional=0; prev="$tok"; continue ;;
    esac
    if [ "$tok" = push ]; then
      case "$prev" in
        git|*/git) in_push=1; skip_next=0; positional=0; prev="$tok"; continue ;;
      esac
    fi
    if [ "$in_push" = 1 ]; then
      if [ "$skip_next" = 1 ]; then skip_next=0; prev="$tok"; continue; fi
      case "$tok" in
        # Flags whose VALUE is a separate following token — skip that value so it is never
        # read as a remote or a branch. (`--flag=value` is a single token and falls into
        # the generic `-*` arm below, carrying its value with it.)
        --repo|-o|--push-option|--receive-pack|--exec)
          skip_next=1; prev="$tok"; continue ;;
        -*) prev="$tok"; continue ;;
      esac
      # First positional after the push token is the remote, not a branch.
      positional=$((positional + 1))
      if [ "$positional" -eq 1 ]; then prev="$tok"; continue; fi
      # Refspec: destination is the dst of src:dst (else the token itself); then strip a
      # leading + (force) and a refs/heads/ prefix to normalize to the bare branch name.
      case "$tok" in
        *:*) dst="${tok##*:}" ;;
        *)   dst="$tok" ;;
      esac
      dst="${dst#+}"
      dst="${dst#refs/heads/}"
      printf '%s\n' "$dst"
    fi
    prev="$tok"
  done
}
