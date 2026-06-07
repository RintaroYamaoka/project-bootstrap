#!/usr/bin/env bash
# Shared resolver for the wip_limit display value shown by the sprint hooks.
#
# "既定 2-3" used to be hardcoded as advisory text in sprint-trigger-reminder.sh
# and block-unplanned-feature-build.sh (plus 4 docs). A project that raises its
# lane count for an experiment had no single declaration the hooks would follow —
# and board.json cannot be that source: it is per-sprint EPHEMERAL state whose
# wip_limit may be a sprint-specific deviation (see docs/sprint/board.json's
# _wip_note) and goes stale when the sprint ends.
#
# `.bootstrap-wip` at the repo root is the project-level declaration: first
# non-comment non-blank line, digits only after trim. Same opt-in idiom as
# .bootstrap-arch / .bootstrap-lane / .bootstrap-protected. Pure bash, jq-free.
#
# Fail-mode: this value is checklist DISPLAY, not a gate's blocking signal —
# the gate blocks on .gate/board.json presence regardless. So absence, non-git
# cwd, or unparseable content all fall OPEN to the default wording; scripts/
# doctor.sh warns on a declaration that exists but cannot be parsed.
#
# Contract:
#   no stdin; locates the declaration via `git rev-parse --show-toplevel` from cwd
#   stdout = "<n> (.bootstrap-wip)" when declared and parseable, else "既定 2-3"
#   return : always 0
#   output is JSON-string-safe by construction: either a fixed literal or
#   digits + a fixed literal (never quotes/backslashes), so callers may embed
#   it in additionalContext without escaping.

# resolve_wip_limit — see header. Writes the display string to stdout.
resolve_wip_limit() {
  local top file line val
  top=$(git rev-parse --show-toplevel 2>/dev/null | tr '\\' '/' | tr -s '/')
  file="$top/.bootstrap-wip"
  if [ -n "$top" ] && [ -f "$file" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      # trim both ends
      line="${line#"${line%%[![:space:]]*}"}"
      line="${line%"${line##*[![:space:]]}"}"
      [ -z "$line" ] && continue
      case "$line" in \#*) continue ;; esac
      val="$line"
      break
    done < "$file"
    case "${val:-}" in
      '' | *[!0-9]*) ;;                                  # unparseable => default (doctor warns)
      *) printf '%s (.bootstrap-wip)' "$val"; return 0 ;;
    esac
  fi
  printf '既定 2-3'
  return 0
}
