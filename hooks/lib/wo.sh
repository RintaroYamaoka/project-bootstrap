#!/usr/bin/env bash
# Shared parser for a Work Order (WO) — the commission subsystem's one artifact.
#
# Single authority on purpose. Two gates read a WO (`block-commit-if-wo-incomplete.sh`
# at the moment of ordering, `block-impl-without-wo.sh` at the moment implementation
# starts) and four skills write one. If each re-implemented "is this section filled",
# one of them would end up looser, and a looser completeness check fails OPEN —
# silently letting an incomplete contract through is precisely the failure this
# subsystem exists to stop.
#
# Format authority: templates/docs/bootstrap/commission/wo/TEMPLATE.md.
# Pure bash + POSIX awk/sed/grep, jq-free (matches the rest of hooks/lib).
#
# Vocabulary used below:
#   section      `## <N>. <title>` for N in 1..12 (WO_SECTION_COUNT)
#   placeholder  a whole line (or whole table cell) of the form `<...>` after list
#                markers / checkboxes / bold labels / `D<N>:` prefixes / backticks are
#                stripped. Angle brackets INSIDE a line (`Promise<void>`) are not
#                placeholders — generics must survive.
#   filled       the section exists, has content, and holds NO placeholder. "Any
#                placeholder anywhere in the section" is deliberately stricter than
#                "every line is a placeholder": section 10 ships with two real
#                boilerplate bullets plus one placeholder (the escalation condition),
#                and the escalation condition is the single field whose absence most
#                reliably burns tokens. A rule that let a section pass on its
#                boilerplate would leave exactly that hole open.

WO_SECTION_COUNT=12

# shellcheck source=lane-match.sh
. "$(dirname "${BASH_SOURCE[0]}")/lane-match.sh"

# --- primitives -------------------------------------------------------------

# _wo_strip_comments — filter stdin, removing <!-- ... --> blocks (inline or spanning
# lines). Guidance prose lives in comments so that authors never have to delete it,
# which means the parser must never see it either.
_wo_strip_comments() {
  awk '
    {
      line = $0
      while (1) {
        if (!inc) {
          i = index(line, "<!--")
          if (i == 0) { print line; break }
          pre = substr(line, 1, i - 1)
          rest = substr(line, i + 4)
          j = index(rest, "-->")
          if (j > 0) { line = pre substr(rest, j + 3); continue }
          if (pre != "") print pre
          inc = 1; break
        } else {
          j = index(line, "-->")
          if (j == 0) break
          line = substr(line, j + 3); inc = 0; continue
        }
      }
    }
  '
}

# wo_section_body <file> <n> — the body lines of section n, comments stripped.
wo_section_body() {
  awk -v n="$2" '
    $0 ~ "^## " n "\\." { inside = 1; next }
    inside && /^## / { inside = 0 }
    inside { print }
  ' "$1" 2>/dev/null | _wo_strip_comments
}

# _wo_has_section <file> <n> — does the heading exist at all? A missing section is
# unfilled, not absent-therefore-fine (fail-closed on structure).
_wo_has_section() {
  grep -qE "^## $2\." "$1" 2>/dev/null
}

# _wo_cell_is_placeholder <text> — is this whole cell/line an unfilled slot?
_wo_cell_is_placeholder() {
  local s="${1//\`/}"
  s=$(printf '%s' "$s" | sed -E 's/^[[:space:]]*([-*+][[:space:]]+)?(\[[ xX]\][[:space:]]*)?(\*\*[^*]*\*\*[[:space:]]*:?[[:space:]]*)?(D[0-9]+[[:space:]]*:[[:space:]]*)?//')
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  case "$s" in
    '<'*'>') return 0 ;;
  esac
  return 1
}

# _wo_line_has_placeholder <line> — table rows are tested cell by cell, so that a
# half-filled row (`| 1 | ok | ok | <state> |`) still reads as unfilled.
_wo_line_has_placeholder() {
  local line="$1" cell cells
  case "$line" in
    '|'*)
      local IFS='|'
      read -ra cells <<< "$line"
      for cell in "${cells[@]}"; do
        _wo_cell_is_placeholder "$cell" && return 0
      done
      return 1
      ;;
  esac
  _wo_cell_is_placeholder "$line"
}

# --- frontmatter ------------------------------------------------------------

# wo_frontmatter <file> <key> — stdout the value, empty when absent or blank.
# Stops at the closing `---`, so a `key: value` line in the body is never mistaken
# for frontmatter.
wo_frontmatter() {
  awk -v k="$2" '
    NR == 1 && $0 == "---" { fm = 1; next }
    fm && $0 == "---" { exit }
    fm && index($0, k ":") == 1 {
      v = substr($0, length(k) + 2)
      gsub(/^[ \t]+|[ \t]+$/, "", v)
      print v; exit
    }
  ' "$1" 2>/dev/null
}

# --- completeness -----------------------------------------------------------

# wo_section_filled <file> <n> — return 0 when filled.
wo_section_filled() {
  local file="$1" n="$2" line content=0
  _wo_has_section "$file" "$n" || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in *[![:space:]]*) ;; *) continue ;; esac
    _wo_line_has_placeholder "$line" && return 1
    content=1
  done < <(wo_section_body "$file" "$n")
  [ "$content" = 1 ]
}

# wo_unfilled_sections <file> — stdout the unfilled section numbers, space separated.
# Empty output = every section is filled.
wo_unfilled_sections() {
  local n out=""
  for n in $(seq 1 "$WO_SECTION_COUNT"); do
    wo_section_filled "$1" "$n" || out="$out $n"
  done
  printf '%s' "${out# }"
}

# --- DoD / oracle identity check (検算) --------------------------------------
# Inherited, deliberately narrowed, from spec-recovery: the four provenance tags are
# dropped, the arithmetic identity is kept. "Every DoD row has exactly one oracle"
# is checkable; "is this oracle any good" is not.

wo_dod_ids() {
  wo_section_body "$1" 8 | sed -nE 's/^[[:space:]]*[-*+][[:space:]]*\[[ xX]\][[:space:]]*(D[0-9]+)[[:space:]]*:.*/\1/p' \
    | tr '\n' ' ' | sed 's/ $//'
}

wo_oracle_ids() {
  wo_section_body "$1" 9 | sed -nE 's/^[[:space:]]*[-*+][[:space:]]*(D[0-9]+)[[:space:]]*:.*/\1/p' \
    | tr '\n' ' ' | sed 's/ $//'
}

_wo_set_minus() {
  local a b found out=""
  for a in $1; do
    found=0
    for b in $2; do [ "$a" = "$b" ] && { found=1; break; }; done
    [ "$found" = 0 ] && out="$out $a"
  done
  printf '%s' "${out# }"
}

wo_dod_without_oracle() { _wo_set_minus "$(wo_dod_ids "$1")" "$(wo_oracle_ids "$1")"; }
wo_oracle_without_dod() { _wo_set_minus "$(wo_oracle_ids "$1")" "$(wo_dod_ids "$1")"; }

# --- pre-review table -------------------------------------------------------

# _wo_prereview_data_rows — stdout the data rows of section 12 (header/separator out).
_wo_prereview_data_rows() {
  wo_section_body "$1" 12 | awk '
    /^[[:space:]]*\|/ {
      row = $0
      probe = row; gsub(/[ \t|:-]/, "", probe)
      if (probe == "") next                      # separator |---|---|
      split(row, c, "|")
      first = c[2]; gsub(/^[ \t]+|[ \t]+$/, "", first)
      if (first == "#") next                     # header
      print row
    }
  '
}

wo_prereview_rows() { _wo_prereview_data_rows "$1" | grep -c . ; }

# wo_prereview_unresolved <file> — stdout the row numbers whose state cell is neither
# `closed` nor `deferred:<id>`. A blank state cell counts as unresolved: silence is
# not consent, and a finding nobody dispositioned is exactly the hole this table
# exists to surface.
wo_prereview_unresolved() {
  _wo_prereview_data_rows "$1" | awk '
    {
      n = split($0, c, "|")
      num = c[2]; gsub(/^[ \t]+|[ \t]+$/, "", num)
      st = (n >= 5) ? c[5] : ""
      gsub(/^[ \t]+|[ \t]+$/, "", st)
      gsub(/`/, "", st)
      if (st == "closed") next
      if (st ~ /^deferred:[A-Za-z0-9_-]+$/) next
      printf "%s ", num
    }
  ' | sed 's/ $//'
}

# --- unknown (未決) references ----------------------------------------------

# wo_prereview_deferred_ids <file> — the ids a pre-review row deferred to, e.g. `deferred:U3`.
# A deferral is only legitimate when it names a gap that actually exists in the ledger; an id
# nobody ever wrote down is the unnamed deferral both predecessor plugins forbade. The gate
# cross-checks these against charter_unknown_ids — the machine-checkable half of "未決を無音で
# 埋めない" that wo_prereview_unresolved alone does not cover (it only checks the SHAPE of the
# cell, so `deferred:whatever` used to pass).
wo_prereview_deferred_ids() {
  _wo_prereview_data_rows "$1" | awk '
    {
      n = split($0, c, "|")
      st = (n >= 5) ? c[5] : ""
      gsub(/^[ \t]+|[ \t]+$/, "", st)
      gsub(/`/, "", st)
      if (st ~ /^deferred:[A-Za-z0-9_-]+$/) { sub(/^deferred:/, "", st); print st }
    }
  ' | sort -u | tr '\n' ' ' | sed 's/ $//'
}

# wo_referenced_unknowns <file> — unknown-ledger ids cited by section 4 only.
# Section 12 also mentions ids (as `deferred:U3`), but a deferred finding is an
# accepted, named gap — it must not block ordering. Only a prerequisite the WO
# declares it depends on does.
wo_referenced_unknowns() {
  wo_section_body "$1" 4 | tr -c 'A-Za-z0-9_' '\n' | grep -xE 'U[0-9]+' | sort -u \
    | tr '\n' ' ' | sed 's/ $//'
}

# charter_open_unknowns <charter-file> — ids in the unknown ledger whose state is not
# CLOSED. Anything that is not literally CLOSED counts as open, including a blank
# cell: the ledger's whole job is that an unresolved question is never filled in
# silently, so an unreadable state must fail toward "still open".
charter_unknown_ids() {
  [ -f "$1" ] || return 0
  awk '
    /^[[:space:]]*\|/ {
      split($0, c, "|")
      id = c[2]; gsub(/^[ \t]+|[ \t]+$/, "", id)
      if (id ~ /^U[0-9]+$/) printf "%s ", id
    }
  ' "$1" | sed 's/ $//'
}

charter_open_unknowns() {
  [ -f "$1" ] || return 0
  awk '
    /^[[:space:]]*\|/ {
      n = split($0, c, "|")
      id = c[2]; gsub(/^[ \t]+|[ \t]+$/, "", id)
      if (id !~ /^U[0-9]+$/) next
      st = (n >= 4) ? c[4] : ""
      gsub(/^[ \t]+|[ \t]+$/, "", st)
      if (st == "CLOSED") next
      printf "%s ", id
    }
  ' "$1" | sed 's/ $//'
}

# --- scope ------------------------------------------------------------------

wo_scope_globs() {
  wo_section_body "$1" 2 | sed -nE 's/^[[:space:]]*[-*+][[:space:]]+//p' | tr -d '`' \
    | sed -E 's/[[:space:]]+$//' | grep -v '^$'
}

# wo_covers_path <file> <rel> — does section 2 declare this path?
# Matching is delegated to lane_allows so the glob semantics here and in the two lane
# gates cannot drift: `order` copies section 2 verbatim into `.bootstrap/lane`, so a
# path this says is in scope must be a path the lane gate also allows.
wo_covers_path() {
  local tmp rc
  tmp=$(mktemp) || return 1
  wo_scope_globs "$1" > "$tmp"
  lane_allows "$2" "$tmp" && rc=0 || rc=1
  rm -f "$tmp"
  return $rc
}
