#!/usr/bin/env bash
# Shared resolver for the opt-in bootstrap markers.
#
# The six root markers (arch / lint / protected / wip / actions, plus the
# worktree-local lane) used to sit flat at the repo root as `.bootstrap-<name>`,
# cluttering every adopting project's top directory. They now live consolidated
# under a single `.bootstrap/` directory (`.bootstrap/<name>`). This keeps the
# project root tidy WITHOUT changing the design: a marker's PRESENCE is still the
# on-switch, and each hook still reads only its own marker (no shared parser, no
# single point of failure — unparseable `.bootstrap/arch` cannot take down the
# lint gate).
#
# Backward compatibility (ADR: consolidate root markers into .bootstrap/): repos
# that already adopted the legacy flat layout must NOT break on plugin upgrade
# (dogfood repos like propagate-ai are live). So resolution prefers the new
# `.bootstrap/<name>` and falls back to the legacy `.bootstrap-<name>`. New wins
# when both exist. The legacy read is a bounded migration aid, slated for removal
# once all dogfood repos have migrated (see the ADR).
#
# resolve_marker <top> <name>
#   stdout = the marker path the caller should read:
#     - <top> empty                 => "" (caller falls open exactly as before)
#     - new `.bootstrap/<name>` present => that path (new wins over legacy)
#     - only legacy present             => the legacy path
#     - neither present                 => the new canonical `.bootstrap/<name>`,
#       so an absence check `[ -f "$(resolve_marker …)" ]` behaves identically to
#       the old hardcoded path.
#   return : always 0.
#
# Pure bash, jq-free (matches the hooks' no-dependency policy). The output is
# JSON-string-safe only insofar as the repo path is — callers that embed it in
# additionalContext should escape as they already do for any filesystem path.
# Include guard — dispatcher が 1 プロセスに複数 gate を source するときの再読込抑止。
[ -n "${_BOOTSTRAP_LIB_RESOLVE_MARKER:-}" ] && return 0
_BOOTSTRAP_LIB_RESOLVE_MARKER=1

resolve_marker() {
  local top="${1%/}" name="$2" new old
  [ -n "$top" ] || return 0
  new="$top/.bootstrap/$name"
  old="$top/.bootstrap-$name"
  if [ -e "$new" ]; then
    printf '%s' "$new"
  elif [ -e "$old" ]; then
    printf '%s' "$old"
  else
    printf '%s' "$new"
  fi
  return 0
}
