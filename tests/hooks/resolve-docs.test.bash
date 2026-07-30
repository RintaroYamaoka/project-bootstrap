#!/usr/bin/env bash
# Unit tests for hooks/lib/resolve-docs.sh — the shared resolver that maps a
# bootstrap-owned docs directory NAME (sprint/verification/handoffs/incidents) to
# the path the gates should read.
#
# Why this exists: those four directories sat flat at docs/<name>, interleaved
# with the adopting project's own docs. They now live consolidated under
# docs/bootstrap/<name>. Every gate's opt-in check is a directory-existence test,
# so a flag-day move would fail OPEN in already-adopted repos — hence a resolver
# that prefers the new layout and falls back to the legacy one (ADR 0020, same
# shape as resolve-marker.sh / ADR 0015).
#
# Contract:
#   resolve_docs_dir <top> <name>
#     - <top> empty                        => empty stdout (caller falls open as before)
#     - new docs/bootstrap/<name> present   => that path            (new wins)
#     - only legacy docs/<name> present     => the legacy path      (backward compat)
#     - neither present                     => the new canonical path, so absence
#                                              checks behave identically to the old
#                                              hardcoded path.
#   resolve_docs_label <top> <name>  => the same answer, repo-relative (for messages)
#   docs_state_face <rel> <name>     => 0 when rel is inside EITHER layout's <name>
#   all always return 0 (docs_state_face returns 0/1 as its answer).

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"
source "$(cd "$DIR/../../hooks" && pwd)/lib/resolve-docs.sh"

mk() { mktemp -d; }

# ---------------------------------------------------------------- resolve_docs_dir

# 1. Empty top => empty output (fail-open passthrough, same as resolve_marker).
test_case "empty top yields empty output"
assert_eq "" "$(resolve_docs_dir "" sprint)"

# 2. Neither layout present => new canonical path. This is what keeps an
#    un-adopted repo's `[ -d ... ]` check false exactly as before.
T="$(mk)"
test_case "neither present yields new canonical path"
assert_eq "$T/docs/bootstrap/sprint" "$(resolve_docs_dir "$T" sprint)"
test_case "absence check on an un-adopted repo is still false"
[ -d "$(resolve_docs_dir "$T" sprint)" ] && R=adopted || R=absent
assert_eq "absent" "$R"

# 3. Only the new layout present => new path.
T="$(mk)"; mkdir -p "$T/docs/bootstrap/sprint"
test_case "new layout resolves to docs/bootstrap/<name>"
assert_eq "$T/docs/bootstrap/sprint" "$(resolve_docs_dir "$T" sprint)"

# 4. Only the legacy layout present => legacy path (the backward-compat case that
#    keeps live dogfood repos' gates armed across the upgrade).
T="$(mk)"; mkdir -p "$T/docs/sprint"
test_case "legacy layout still resolves (gate stays armed after upgrade)"
assert_eq "$T/docs/sprint" "$(resolve_docs_dir "$T" sprint)"
test_case "legacy layout satisfies the opt-in existence check"
[ -d "$(resolve_docs_dir "$T" sprint)" ] && R=adopted || R=absent
assert_eq "adopted" "$R"

# 5. Both present => new wins (a half-migrated repo must not read two sources).
T="$(mk)"; mkdir -p "$T/docs/bootstrap/verification" "$T/docs/verification"
test_case "both present: new wins over legacy"
assert_eq "$T/docs/bootstrap/verification" "$(resolve_docs_dir "$T" verification)"

# 6. Resolution is per-name, not per-repo: a repo may migrate sprint but not
#    verification, and each gate must follow its own directory.
T="$(mk)"; mkdir -p "$T/docs/bootstrap/sprint" "$T/docs/verification"
test_case "per-name resolution: sprint migrated"
assert_eq "$T/docs/bootstrap/sprint" "$(resolve_docs_dir "$T" sprint)"
test_case "per-name resolution: verification still legacy"
assert_eq "$T/docs/verification" "$(resolve_docs_dir "$T" verification)"

# 7. A trailing slash on <top> must not produce a doubled separator (callers pass
#    `git rev-parse --show-toplevel` output, which is normalised, but the marker
#    resolver tolerates this and so must this one).
T="$(mk)"; mkdir -p "$T/docs/bootstrap/handoffs"
test_case "trailing slash on top is normalised"
assert_eq "$T/docs/bootstrap/handoffs" "$(resolve_docs_dir "$T/" handoffs)"

# 8. A FILE (not a directory) at the new path must not shadow a real legacy
#    directory — the opt-in signal is a directory, and `[ -e ]` would mis-resolve
#    a stray file into a path no gate can read.
T="$(mk)"; mkdir -p "$T/docs/bootstrap" "$T/docs/incidents"; : > "$T/docs/bootstrap/incidents"
test_case "a stray file at the new path does not shadow the legacy directory"
assert_eq "$T/docs/incidents" "$(resolve_docs_dir "$T" incidents)"

# -------------------------------------------------------------- resolve_docs_label

# 9. The label is what block messages print. It must name the path that actually
#    holds the files, per layout — sending a legacy repo to docs/bootstrap/sprint
#    points the human at an empty directory.
T="$(mk)"; mkdir -p "$T/docs/sprint"
test_case "label follows the legacy layout when that is what exists"
assert_eq "docs/sprint" "$(resolve_docs_label "$T" sprint)"
T="$(mk)"; mkdir -p "$T/docs/bootstrap/sprint"
test_case "label follows the new layout when that is what exists"
assert_eq "docs/bootstrap/sprint" "$(resolve_docs_label "$T" sprint)"
T="$(mk)"
test_case "label on an un-adopted repo names the new canonical path"
assert_eq "docs/bootstrap/verification" "$(resolve_docs_label "$T" verification)"
test_case "label with empty top yields empty"
assert_eq "" "$(resolve_docs_label "" sprint)"

# --------------------------------------------------------------- docs_state_face

# 10. Both layouts are exempt. The sprint gates must never block the write to
#     their own runtime state, under either layout.
test_case "legacy sprint state is recognised"
docs_state_face "docs/sprint/board.json" sprint && R=in || R=out
assert_eq "in" "$R"
test_case "new sprint state is recognised"
docs_state_face "docs/bootstrap/sprint/board.json" sprint && R=in || R=out
assert_eq "in" "$R"
test_case "nested legacy form is recognised (matches the previous glob)"
docs_state_face "sub/docs/sprint/.gate" sprint && R=in || R=out
assert_eq "in" "$R"
test_case "nested new form is recognised"
docs_state_face "sub/docs/bootstrap/sprint/reviews/feat_x.md" sprint && R=in || R=out
assert_eq "in" "$R"

# 11. The predicate must be name-scoped: verification state is not sprint state.
test_case "a different bootstrap directory is not this one"
docs_state_face "docs/bootstrap/verification/feat_x.md" sprint && R=in || R=out
assert_eq "out" "$R"

# 12. Source files must NOT be exempted — this predicate widens fail-open, so a
#     loose match here would silently disarm the gate it guards.
test_case "a source path is not sprint state"
docs_state_face "src/core/thing.ts" sprint && R=in || R=out
assert_eq "out" "$R"
test_case "a sibling docs directory is not sprint state"
docs_state_face "docs/sprintlog/notes.md" sprint && R=in || R=out
assert_eq "out" "$R"
test_case "the directory itself without a child is not a state write"
docs_state_face "docs/bootstrap/sprint" sprint && R=in || R=out
assert_eq "out" "$R"

# 13. The exemption must hold before the directory exists. The first board.json
#     write happens while docs/bootstrap/sprint/ is still absent, so this
#     predicate cannot consult the filesystem.
T="$(mk)"; mkdir -p "$T/docs/sprint"   # legacy on disk, writing the NEW layout
test_case "new-layout state is exempt even while only the legacy dir exists"
docs_state_face "docs/bootstrap/sprint/board.json" sprint && R=in || R=out
assert_eq "in" "$R"

finish
