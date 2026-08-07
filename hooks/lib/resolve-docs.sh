#!/usr/bin/env bash
# Shared resolver for the bootstrap-owned docs directories.
#
# Five directories are this plugin's own working surfaces: `sprint` (board.json /
# .gate / reviews), `verification` (per-branch plans + contracts), `commission`
# (charter + work orders + metrics, ADR 0022), `handoffs` and `incidents`. They used
# to sit flat at `docs/<name>`, interleaved with whatever else the adopting project
# keeps in docs/ (requirements, design, glossary). They now live consolidated under a
# single `docs/bootstrap/` parent (`docs/bootstrap/<name>`).
#
# This is the docs-side twin of resolve-marker.sh (ADR 0015 did the same for the
# six root markers). The design is unchanged: a directory's PRESENCE is still the
# opt-in switch, each gate still reads only its own directory, and there is no
# shared parser and so no single point of failure.
#
# `docs/decisions/` is deliberately NOT in this set. ADRs are a general engineering
# convention, not a bootstrap artifact — other tooling and humans write there too,
# and splitting the destination would fork one repo's decision record in two.
#
# Backward compatibility (ADR 0020): repos that already adopted the flat layout
# must NOT lose their gates the moment the plugin updates. Every gate's opt-in
# check is a directory-existence test, so a silent move would fail OPEN — the
# worst fail-mode this plugin has (memory `feedback_gate_distribution_coverage`).
# Resolution therefore prefers the new `docs/bootstrap/<name>` and falls back to
# the legacy `docs/<name>`. New wins when both exist. The legacy read is a bounded
# migration aid, slated for removal once every dogfood repo has migrated (see the
# ADR for the removal condition).
#
# resolve_docs_dir <top> <name>
#   stdout = the directory path the caller should read:
#     - <top> empty                        => "" (caller falls open exactly as before)
#     - new `docs/bootstrap/<name>` present => that path (new wins over legacy)
#     - only legacy `docs/<name>` present   => the legacy path
#     - neither present                     => the new canonical `docs/bootstrap/<name>`,
#       so an absence check `[ -d "$(resolve_docs_dir …)" ]` behaves identically to
#       the old hardcoded path.
#   return : always 0.
#
# Pure bash, jq-free (matches the hooks' no-dependency policy).
resolve_docs_dir() {
  local top="${1%/}" name="$2" new old
  [ -n "$top" ] || return 0
  new="$top/docs/bootstrap/$name"
  old="$top/docs/$name"
  if [ -d "$new" ]; then
    printf '%s' "$new"
  elif [ -d "$old" ]; then
    printf '%s' "$old"
  else
    printf '%s' "$new"
  fi
  return 0
}

# resolve_docs_label <top> <name>
#   The repo-relative form of resolve_docs_dir, for block messages and advisories
#   that must name a path the human can actually `ls`. Telling a legacy repo to
#   look in docs/bootstrap/sprint/ (or a migrated one to look in docs/sprint/)
#   sends them to an empty directory, so the message must follow the same
#   resolution the gate used.
#   stdout = e.g. "docs/bootstrap/sprint" or "docs/sprint"; "" when <top> is empty.
#   return : always 0.
resolve_docs_label() {
  local top="${1%/}" dir
  dir="$(resolve_docs_dir "$top" "$2")"
  [ -n "$dir" ] || return 0
  printf '%s' "${dir#"$top"/}"
  return 0
}

# docs_state_face <rel> <name>
#   Is this repo-relative path inside the bootstrap-owned directory <name>, under
#   EITHER layout? The sprint gates use this to exempt their own runtime state
#   (board.json / .gate / reviews) from blocking — a gate must never stop the
#   write that clears it.
#
#   Both layouts are matched unconditionally rather than resolved against the
#   filesystem, because the caller is classifying a path that may not exist yet
#   (PreToolUse fires before the write, and the very first board.json write
#   happens while docs/bootstrap/sprint/ is still absent — resolving there would
#   send the check to the legacy branch and block the file that creates the new
#   layout). Matching both is strictly safer: this predicate only ever widens
#   fail-open exemptions on paths this plugin owns.
#   return : 0 when inside, 1 otherwise.
docs_state_face() {
  local rel="$1" name="$2"
  case "$rel" in
    docs/"$name"/*|*/docs/"$name"/*) return 0 ;;
    docs/bootstrap/"$name"/*|*/docs/bootstrap/"$name"/*) return 0 ;;
  esac
  return 1
}
