#!/usr/bin/env bash
# Shared judge for "is a single .gate entry LIVE EVIDENCE of a sprint-gate decision".
#
# Born from docs/bootstrap/incidents/2026-06-11-gate-broad-glob-permanent-fail-open: the sprint
# gate used to honor a recorded .gate entry FOREVER and at ANY breadth. A `.gate` line
# is a per-feature ephemeral judgment ("this scope was judged sequential"), but with no
# expiry and no breadth bound, one `src/**` line recorded for one feature on 2026-06-02
# silently disarmed the gate for a consumer repo's entire source tree, permanently —
# 10+ new source files were then created without a single gate decision. This is the
# 4th member of the gate-silence class (advisory forgotten → not deployed → stale state
# → unbounded state). The rule is therefore: an entry counts only while it is bounded
# in TIME (date column within GATE_TTL_DAYS) and in SPACE (feature-scoped glob).
# Re-recording an expired line is one printf — and that re-record IS the re-judgment.
#
# Contract:
#   gate_date_fresh <YYYY-MM-DD> [today]
#     return 0 = strict YYYY-MM-DD and 0 <= (today - date) <= GATE_TTL_DAYS
#     return 1 = malformed / absent / future-dated / older than TTL
#     [today] is for tests; defaults to date +%F.
#   gate_scope_ok <glob>
#     return 0 = exact path (no wildcard — narrowest possible), or the literal
#                directory prefix before the first wildcard segment has >= 2 segments
#     return 1 = tree-wide (src/**, scripts/**, **, *, *.ts, src/*/x, ...)
#   no stdout. Pure bash, jq-free, no GNU-date arithmetic (BSD-safe: day math is done
#   on Julian Day Numbers computed in shell integer arithmetic).

GATE_TTL_DAYS=3

# _gate_jdn YYYY-MM-DD — Julian Day Number, pure integer arithmetic.
_gate_jdn() {
  local ymd="$1"
  local y="${ymd%%-*}" rest="${ymd#*-}"
  local m="${rest%%-*}" d="${rest#*-}"
  y=$((10#$y)); m=$((10#$m)); d=$((10#$d))
  local a=$(( (14 - m) / 12 ))
  local yy=$(( y + 4800 - a ))
  local mm=$(( m + 12*a - 3 ))
  printf '%s' $(( d + (153*mm + 2)/5 + 365*yy + yy/4 - yy/100 + yy/400 - 32045 ))
}

# gate_date_fresh — see header.
gate_date_fresh() {
  local dt="${1:-}" today="${2:-}"
  case "$dt" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *) return 1 ;;
  esac
  [ -n "$today" ] || today="$(date +%F)"
  local age=$(( $(_gate_jdn "$today") - $(_gate_jdn "$dt") ))
  [ "$age" -ge 0 ] && [ "$age" -le "$GATE_TTL_DAYS" ]
}

# gate_scope_ok — see header. String-walk only: the pattern is never expanded
# unquoted (it contains wildcards that would glob against the cwd).
gate_scope_ok() {
  local pat="${1:-}"
  [ -n "$pat" ] || return 1
  case "$pat" in
    *"*"*|*"?"*|*"["*) ;;   # has wildcard -> needs a >= 2-segment literal prefix
    *) return 0 ;;          # exact path = narrowest possible evidence
  esac
  local rest="$pat" seg n=0
  while [ -n "$rest" ]; do
    seg="${rest%%/*}"
    case "$seg" in
      *"*"*|*"?"*|*"["*) break ;;
      "") ;;
      *) n=$((n+1)) ;;
    esac
    case "$rest" in
      */*) rest="${rest#*/}" ;;
      *) break ;;
    esac
  done
  [ "$n" -ge 2 ]
}
