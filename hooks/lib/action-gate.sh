#!/usr/bin/env bash
# Shared authority for "does this command perform a repeat-prone ACTION, and which one?"
# Sole consumer today is hooks/inject-action-memory.sh (the PreToolUse memo injector);
# scripts/doctor.sh sources it for the orphan-entry audit. Single authority so the hook
# and the doctor cannot drift on what counts as a matched action or a valid action-key —
# drift in a gate signal IS the silent-bypass class this repo treats as a first-class bug
# (same policy as lib/merge-targets.sh, lib/protected-branch.sh, lib/parse-command.sh).
#
# WHY this exists (the incident this lane answers): a deploy-author bug recurred ~7 times
# even though a memory documented the exact fix — the fix was never surfaced AT the moment
# the prod deploy ran, so each new session re-discovered it from scratch. This lib lets the
# injector put the recorded memo in front of the actor right before a repeat-prone action.
#
# WHY a shared TOKENIZER mapping to a CLOSED enum, NOT per-entry user regex (the key design
# decision): if each registry line carried its own match regex, every consumer repo would be
# authoring unreviewed matchers — re-importing the exact greedy-sed / "string proxy for an
# action" bug class that merge-targets.sh / protected-branch.sh were written to kill (a
# `.*deploy.*` would match `echo deploy`, an un-anchored `git` would match `legit`). So the
# MATCHER is plugin-owned code reviewed once; the registry only ARMS an existing enum key.
# Adding a key (e.g. a new prod-* action) is a reviewed plugin-level enum change here, never
# inline matching in a consumer's file.
#
# WHY no fail-CLOSED here: the only consumer is a VISIBILITY hook that never blocks (ADR
# 0010 / ADR 0001 — an ack/block token is self-issuable by the very actor being gated, so
# comprehension stays irreducible and we do not pretend to enforce it). A non-match or an
# absent registry therefore fails OPEN/silent by design; there is no unsafe side to guard.
#
# The tokenizer mirrors lib/merge-targets.sh exactly: strip leading `VAR=val` env-prefixes,
# accept path-prefixed binaries (/usr/local/bin/vercel, ./node_modules/.bin/prisma), unwrap
# a `bash -c "..."` / `npx <bin>` launcher, walk EVERY segment of a compound command, and
# word-split under noglob so a `*`/`?` in the command is not expanded against the filesystem.
# Pure bash, jq-free.

# --- the CLOSED, plugin-owned ACTION-KEY enum --------------------------------------
# The complete vocabulary of repeat-prone actions this plugin can surface a memo for. A
# registry line may only ARM a key listed here; an armed key NOT in this list is an orphan
# (doctor reports it — see registry_orphan_keys). Extending the vocabulary is a reviewed
# edit to THIS array (and the matcher arm below), never a consumer-side regex.
ACTION_KEY_ENUM="prod-deploy prod-db-migrate"

# action_key_is_known <key> — return 0 if <key> is a member of the CLOSED enum.
action_key_is_known() {
  local k
  for k in $ACTION_KEY_ENUM; do
    [ "$k" = "$1" ] && return 0
  done
  return 1
}

# _action_tokenize <command> — emit the normalized argv of EVERY segment of a (possibly
# compound) command, one token per line, with shell separators re-emitted as the literal
# word `;SEP;` so the matcher can reset its per-segment state at a boundary. Mirrors the
# normalize+noglob+word-split of lib/merge-targets.sh; additionally it de-quotes tokens,
# strips leading `VAR=val` env-prefixes at the start of each segment, and unwraps
# `bash -c <script>` / `npx <bin>` / `pnpm dlx <bin>` launchers so the real action verb is
# reached. Like merge-targets.sh, a separator INSIDE a quoted argument is indistinguishable
# from a real one without a full shell parser (documented limit; this hook never blocks, so
# a mis-split only means a possibly-missed memo = fail-open, never a wrong block).
_action_tokenize() {
  local cmd="$1" norm noglob=0 tok seg_start=1
  # Pad shell separators so they tokenize as standalone words (vercel deploy;prisma migrate).
  norm="$(printf '%s' "$cmd" | sed -E 's/(\&\&|\|\||;|\||\&)/ \&\& /g')"
  case $- in *f*) ;; *) noglob=1; set -f ;; esac
  # shellcheck disable=SC2086
  set -- $norm
  [ "$noglob" = 1 ] && set +f
  while [ $# -gt 0 ]; do
    tok="$1"; shift
    case "$tok" in
      '&&'|'||'|';'|'|'|'&')
        printf '%s\n' ';SEP;'; seg_start=1; continue ;;
    esac
    # Strip surrounding quote chars from every token. Word-splitting an unquoted `$norm`
    # does NOT honor quotes, so a `bash -c "vercel deploy"` arrives as `bash -c "vercel
    # deploy"` (quote chars glued to the words). They are pure noise for structural
    # matching (binary names + subcommand/flag words), so we drop a single leading and
    # trailing `"` or `'`. This also de-quotes the script of a `bash -c` so its verb is
    # reached as an ordinary segment head below.
    case "$tok" in '"'*|"'"*) tok="${tok#\"}"; tok="${tok#\'}" ;; esac
    case "$tok" in *'"'|*"'") tok="${tok%\"}"; tok="${tok%\'}" ;; esac
    [ -z "$tok" ] && continue
    if [ "$seg_start" = 1 ]; then
      # Strip leading `VAR=val` env-prefixes (FOO=bar BAZ=qux vercel ...). A token is an
      # env-prefix only at segment start: NAME=... where NAME is a valid shell identifier.
      case "$tok" in
        [A-Za-z_]*=*)
          case "${tok%%=*}" in
            *[!A-Za-z0-9_]*) ;;   # name has a non-identifier char -> not an env-prefix
            *) continue ;;        # genuine env-prefix -> drop, stay at segment start
          esac ;;
      esac
      # Unwrap a launcher so the real binary is the next thing we see, then STAY at segment
      # start so the following token becomes the head. `bash -c <script>`: drop `bash` and
      # `-c`; the de-quoted script words follow in-line and the script's first word becomes
      # the head (good enough for the single-action verbs we key on). `npx <bin>` / `pnpm
      # dlx <bin>`: drop the launcher word(s) and any leading flags.
      case "$tok" in
        bash|sh|/*/bash|/*/sh|*/bash|*/sh)
          if [ "${1:-}" = "-c" ]; then shift; continue; fi
          ;;
        npx|/*/npx|*/npx)
          while [ $# -gt 0 ]; do
            case "${1:-}" in -*) shift ;; *) break ;; esac
          done
          continue ;;
        pnpm|/*/pnpm|*/pnpm)
          if [ "${1:-}" = "dlx" ]; then shift; continue; fi
          ;;
      esac
      seg_start=0
    fi
    printf '%s\n' "$tok"
  done
}

# action_key_for_command <command> — print the single matched ACTION-KEY (from the CLOSED
# enum), or nothing if no segment is a repeat-prone action. The match is structural per
# segment: the binary (basename of the segment head, path-prefix stripped) plus the presence
# of the required subcommand/flag tokens within THAT segment. This is the only place a
# command string is turned into a key; consumers never pattern-match raw commands themselves.
action_key_for_command() {
  local head="" base want_prod=0 has_deploy=0 has_migrate_sub=0 t
  # We accumulate per-segment facts, then decide at each ;SEP; boundary (and at end).
  _decide() {
    case "$head" in
      vercel)
        # prod deploy = `vercel deploy` with a production flag in the same segment. A bare
        # `vercel deploy` is a PREVIEW deploy and must NOT match (no false memo on preview).
        if [ "$has_deploy" = 1 ] && [ "$want_prod" = 1 ]; then printf 'prod-deploy'; return 0; fi ;;
      prisma)
        # prod db migrate = `prisma migrate deploy` (the apply-to-prod form; `migrate dev`
        # and `generate` are dev-only and must NOT match).
        if [ "$has_migrate_sub" = 1 ] && [ "$has_deploy" = 1 ]; then printf 'prod-db-migrate'; return 0; fi ;;
    esac
    return 1
  }
  while IFS= read -r t; do
    if [ "$t" = ';SEP;' ]; then
      _decide && return 0
      head=""; want_prod=0; has_deploy=0; has_migrate_sub=0
      continue
    fi
    if [ -z "$head" ]; then
      base="${t##*/}"            # strip any path prefix -> bare binary name
      head="$base"
      continue
    fi
    case "$t" in
      --prod|--production|--prod=*|prod|production) want_prod=1 ;;
      deploy) has_deploy=1 ;;
      migrate) has_migrate_sub=1 ;;
    esac
  done < <(_action_tokenize "$1")
  _decide && return 0
  return 0
}

# --- the per-repo registry (opt-in) -------------------------------------------------
# Lives at <repo-root>/.bootstrap-actions (an opt-in marker — absent = this mechanism is
# off and the injector is silent, so non-adopting repos are never disturbed). One armed
# action per line:  <action-key> | <memory-slug-or-path> | <note>
# Surrounding whitespace is trimmed; blank lines and `#` comments are ignored. The slug is
# advisory text injected verbatim (the injector does NOT read the memory file — it points
# the actor at it; resolving/reading is the actor's job, comprehension stays irreducible).

_registry_path() { printf '%s/.bootstrap-actions' "${1%/}"; }

# registry_memo_for_key <repo-root> <action-key> — print the memo to inject for <action-key>
# if the repo's registry ARMS it, else print nothing (opt-in / silent). The printed memo is
# "<slug> — <note>" so the actor sees both the pointer and the one-line reminder. The FIRST
# matching line wins (a repo arming a key twice is its own concern; we do not merge).
registry_memo_for_key() {
  local repo="$1" want="$2" file line k slug note
  file="$(_registry_path "$repo")"
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"; line="${line%"${line##*[![:space:]]}"}"
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    # Split on the FIRST two pipes; trim each field.
    k="${line%%|*}";              k="${k%"${k##*[![:space:]]}"}"; k="${k#"${k%%[![:space:]]*}"}"
    [ "$k" = "$want" ] || continue
    line="${line#*|}"
    slug="${line%%|*}";           slug="${slug%"${slug##*[![:space:]]}"}"; slug="${slug#"${slug%%[![:space:]]*}"}"
    note="${line#*|}";            note="${note%"${note##*[![:space:]]}"}"; note="${note#"${note%%[![:space:]]*}"}"
    if [ -n "$note" ] && [ "$note" != "$slug" ]; then
      printf '%s — %s' "$slug" "$note"
    else
      printf '%s' "$slug"
    fi
    return 0
  done < "$file"
  return 0
}

# registry_orphan_keys <repo-root> — print every armed key that is NOT in the CLOSED enum,
# one per line (for the doctor orphan audit). An orphan means a consumer armed a key that
# the plugin's matcher will NEVER produce, so the memo can never fire — a silent dead entry
# this surfaces (never blocks). No registry / all-valid => prints nothing.
registry_orphan_keys() {
  local repo="$1" file line k
  file="$(_registry_path "$repo")"
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"; line="${line%"${line##*[![:space:]]}"}"
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    k="${line%%|*}"; k="${k%"${k##*[![:space:]]}"}"; k="${k#"${k%%[![:space:]]*}"}"
    [ -z "$k" ] && continue
    action_key_is_known "$k" || printf '%s\n' "$k"
  done < "$file"
  return 0
}
