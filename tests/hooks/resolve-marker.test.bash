#!/usr/bin/env bash
# Unit tests for hooks/lib/resolve-marker.sh — the shared resolver that maps an
# opt-in marker NAME (arch/lint/protected/wip/actions/lane) to the path the hooks
# should read.
#
# Why this exists: the six root markers (.bootstrap-arch / -lint / -protected /
# -wip / -actions, plus the worktree-local .bootstrap-lane) cluttered the project
# root. They now live consolidated under a `.bootstrap/` directory (.bootstrap/arch
# etc). To avoid a flag-day break for repos that already adopted the legacy flat
# layout, every hook resolves a marker through this lib, which prefers the new
# .bootstrap/<name> and falls back to the legacy .bootstrap-<name>.
#
# Contract:
#   resolve_marker <top> <name>
#     - <top> empty            => empty stdout (caller falls open exactly as before)
#     - new .bootstrap/<name>  present => that path           (new wins)
#     - only legacy present            => the legacy path     (backward compat)
#     - neither present                => the new canonical path (.bootstrap/<name>),
#                                         so absence checks `[ -f "$(resolve_marker …)" ]`
#                                         behave identically to the old direct path.
#   always returns 0.

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"
source "$(cd "$DIR/../../hooks" && pwd)/lib/resolve-marker.sh"

mk() { mktemp -d; }

# 1. Empty top => empty output (fail-open passthrough).
test_case "empty top yields empty output"
assert_eq "" "$(resolve_marker "" arch)"

# 2. Neither layout present => new canonical path.
T="$(mk)"
test_case "neither present yields new canonical path"
assert_eq "$T/.bootstrap/arch" "$(resolve_marker "$T" arch)"

# 3. Only new present => new path.
T="$(mk)"; mkdir -p "$T/.bootstrap"; : > "$T/.bootstrap/lint"
test_case "new-only yields new path"
assert_eq "$T/.bootstrap/lint" "$(resolve_marker "$T" lint)"

# 4. Only legacy present => legacy path (backward compat).
T="$(mk)"; : > "$T/.bootstrap-protected"
test_case "legacy-only yields legacy path"
assert_eq "$T/.bootstrap-protected" "$(resolve_marker "$T" protected)"

# 5. Both present => new wins.
T="$(mk)"; mkdir -p "$T/.bootstrap"; : > "$T/.bootstrap/wip"; : > "$T/.bootstrap-wip"
test_case "both present prefers new"
assert_eq "$T/.bootstrap/wip" "$(resolve_marker "$T" wip)"

# 6. A directory marker (e.g. .bootstrap/ itself absent but file dir) resolves by -e.
#    .bootstrap/lane as a worktree-local marker is resolved the same way.
T="$(mk)"; : > "$T/.bootstrap-lane"
test_case "legacy lane resolves to legacy path"
assert_eq "$T/.bootstrap-lane" "$(resolve_marker "$T" lane)"

# 7. Trailing slash on top is tolerated.
T="$(mk)"; mkdir -p "$T/.bootstrap"; : > "$T/.bootstrap/arch"
test_case "trailing slash on top is normalized"
assert_eq "$T/.bootstrap/arch" "$(resolve_marker "$T/" arch)"

finish
