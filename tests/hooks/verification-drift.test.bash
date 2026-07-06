#!/usr/bin/env bash
# Unit tests for hooks/lib/verification-drift.sh — the SessionStart doctor's
# "unverified trunk change" judge: source-face changes on the current branch with no
# verification judgment recorded, in a repo that adopted docs/verification/.
#
# This is VISIBILITY, not enforcement, so we assert on the presence/absence of the advisory
# text and on the SILENCE bars (no adoption / no source change / plan present / non-git).
# We build throwaway repos with a LOCAL refs/remotes/origin/main (no network — the lib
# never fetches), mirroring repo-drift.test.bash.

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"
source "$(cd "$DIR/../../hooks" && pwd)/lib/verification-drift.sh"

git config --global user.email >/dev/null 2>&1 || git config --global user.email "test@example.com"
git config --global user.name  >/dev/null 2>&1 || git config --global user.name  "test"

# mkrepo — fresh repo, one commit on main, docs/verification/ NOT yet adopted. echoes path.
mkrepo() {
  local r; r="$(mktemp -d)"
  git -C "$r" init -q -b main
  git -C "$r" -c user.email=t@e.x -c user.name=t commit -q --allow-empty -m c0
  printf '%s' "$r"
}
adopt() { mkdir -p "$1/docs/verification"; }
commit_file() { # commit_file <repo> <path> <content>
  printf '%s\n' "$3" > "$1/$2"
  git -C "$1" add "$2"
  git -C "$1" -c user.email=t@e.x -c user.name=t commit -q -m "add $2"
}
spoke() { case "$1" in *"未判断の trunk source"*) return 0 ;; *) return 1 ;; esac; }

# 1. Adopted + uncommitted source + no plan => speaks. (Also the local-only / no-origin
#    case: mkrepo has no origin ref, so only the uncommitted path can fire — it must.)
R="$(mkrepo)"; adopt "$R"
printf 'export const x = 1\n' > "$R/app.ts"
OUT="$(verification_drift_report "$R")"
test_case "adopted + uncommitted source + no plan speaks"
if spoke "$OUT"; then assert_eq spoke spoke; else assert_eq spoke silent; fi
test_case "report names the triggering source file"
case "$OUT" in *"app.ts"*) assert_eq ok ok ;; *) assert_eq ok FAIL ;; esac

# 2. Doc-only change => silent.
R="$(mkrepo)"; adopt "$R"
printf '# notes\n' > "$R/README.md"
test_case "doc-only change is silent"
assert_eq "" "$(verification_drift_report "$R")"

# 3. A non-empty plan (>=1 row) for the branch => silent (the decision is being made).
R="$(mkrepo)"; adopt "$R"
printf 'export const x = 1\n' > "$R/app.ts"
printf 'DROP | unit | trivial | n/a | ai | low risk, internal\n' > "$R/docs/verification/main.md"
test_case "recorded judgment (non-empty plan) is silent"
assert_eq "" "$(verification_drift_report "$R")"

# 4. docs/verification not adopted => silent (opt-in), even with source changes.
R="$(mkrepo)"
printf 'export const x = 1\n' > "$R/app.ts"
test_case "no verification adoption is silent (opt-in)"
assert_eq "" "$(verification_drift_report "$R")"

# 5. Empty (comment-only) plan => speaks (a ritual file is not a judgment).
R="$(mkrepo)"; adopt "$R"
printf 'export const x = 1\n' > "$R/app.ts"
printf '# verification plan — nothing here yet\n' > "$R/docs/verification/main.md"
OUT="$(verification_drift_report "$R")"
test_case "empty comment-only plan still speaks"
if spoke "$OUT"; then assert_eq spoke spoke; else assert_eq spoke silent; fi

# 6. Clean tree, no source change => silent.
R="$(mkrepo)"; adopt "$R"
test_case "clean tree is silent"
assert_eq "" "$(verification_drift_report "$R")"

# 7. Committed-ahead source vs origin/main + no plan => speaks (tests the committed path
#    specifically: the working tree is clean after the commit).
R="$(mkrepo)"; adopt "$R"
git -C "$R" update-ref refs/remotes/origin/main "$(git -C "$R" rev-parse HEAD)"
commit_file "$R" feature.ts 'export const y = 2'
OUT="$(verification_drift_report "$R")"
test_case "committed-ahead source vs origin/main speaks"
if spoke "$OUT"; then assert_eq spoke spoke; else assert_eq spoke silent; fi

# 8. Committed-ahead but doc-only => silent.
R="$(mkrepo)"; adopt "$R"
git -C "$R" update-ref refs/remotes/origin/main "$(git -C "$R" rev-parse HEAD)"
commit_file "$R" NOTES.md '# doc only'
test_case "committed-ahead doc-only is silent"
assert_eq "" "$(verification_drift_report "$R")"

# 9. Non-git dir => silent (fail-open).
NG="$(mktemp -d)"; mkdir -p "$NG/docs/verification"; printf 'x\n' > "$NG/app.ts"
test_case "non-git dir is silent"
assert_eq "" "$(verification_drift_report "$NG")"

# ── D4: async / silent-skip blind spot (ADR 0007 amendment) ───────────────────────────
# A POPULATED plan (>=1 data row) with an async-kind row but NO monitor row carrying a real
# (field-4 != n/a) oracle is a blind spot: a cron skip / a stalled queue under a live
# heartbeat goes unobserved. The doctor advises on exactly that shape, keyed ONLY on the
# controlled-vocab kind field (never a prose scan), gated on a source-face change, advisory.

# 10. async row, no monitor, with a source change => the async advisory fires.
R="$(mkrepo)"; adopt "$R"
printf 'export const x = 1\n' > "$R/app.ts"
printf 'TODO | async | cron sends the reminder | n/a | ai |\n' > "$R/docs/verification/main.md"
OUT="$(verification_drift_report "$R")"
test_case "async-without-monitor advisory fires on a populated plan"
case "$OUT" in *async*) assert_eq ok ok ;; *) assert_eq ok FAIL ;; esac

# 11. async row WITH a monitor row carrying a real oracle => silent on the async axis.
R="$(mkrepo)"; adopt "$R"
printf 'export const x = 1\n' > "$R/app.ts"
cat > "$R/docs/verification/main.md" <<'EOF'
PASS | async   | cron sends the reminder        | n/a | ai | ran
PASS | monitor | CV>0 but bookings==0 alarm     | daily rollup alert | ai | wired
EOF
test_case "async WITH a real monitor oracle is silent on the async axis"
case "$(verification_drift_report "$R")" in *async*) assert_eq ok FAIL ;; *) assert_eq ok ok ;; esac

# 12. A DROP row whose behaviour text contains the word 'drop' must NOT false-fire the
#     async advisory (the old lexicon scan bug). No async kind here at all.
R="$(mkrepo)"; adopt "$R"
printf 'export const x = 1\n' > "$R/app.ts"
cat > "$R/docs/verification/main.md" <<'EOF'
PASS | unit | parse the row | known | ai | ok
DROP | unit | drop / skip / filter the pixel exactness | n/a | ai | low risk, not worth it
EOF
test_case "a DROP row containing 'drop/skip/filter' does NOT fire the async advisory"
case "$(verification_drift_report "$R")" in *async*) assert_eq ok FAIL ;; *) assert_eq ok ok ;; esac

# 13. async row but the change is DOC-ONLY => silent (gated on a source-face change).
R="$(mkrepo)"; adopt "$R"
printf '# notes\n' > "$R/README.md"
printf 'TODO | async | cron sends the reminder | n/a | ai |\n' > "$R/docs/verification/main.md"
test_case "async advisory is silent on a docs-only branch"
assert_eq "" "$(verification_drift_report "$R")"

# 14. async row with a monitor row whose oracle is the literal 'n/a' => NOT a real oracle,
#     so the async advisory still fires (a placeholder monitor does not cover the blind spot).
R="$(mkrepo)"; adopt "$R"
printf 'export const x = 1\n' > "$R/app.ts"
cat > "$R/docs/verification/main.md" <<'EOF'
TODO | async   | cron sends the reminder | n/a | ai |
TODO | monitor | someday wire an alert   | n/a | ai |
EOF
test_case "async with a placeholder (n/a) monitor oracle still fires"
case "$(verification_drift_report "$R")" in *async*) assert_eq ok ok ;; *) assert_eq ok FAIL ;; esac

# 15. The async advisory is ADVISORY: verification_drift_report always returns 0 (never 2).
R="$(mkrepo)"; adopt "$R"
printf 'export const x = 1\n' > "$R/app.ts"
printf 'TODO | async | cron sends the reminder | n/a | ai |\n' > "$R/docs/verification/main.md"
verification_drift_report "$R" >/dev/null 2>&1
test_case "verification_drift_report returns 0 even when the async advisory fires"
assert_eq 0 "$?"

# ── AXIS 3: held-out / metamorphic blind spot (7th seam / ADR 0016) ────────────────────
# A POPULATED plan with a kind=gameable row (author declared a special-case/hardcode-prone
# oracle) but NO kind=metamorphic row is a blind spot: a decided-in-advance answer passes
# the same-input test green. Keyed ONLY on the controlled-vocab kind field, gated on a
# source-face change, advisory. Same shape as the async axis (declared risk, no mitigation).
gamed() { case "$1" in *"テストゲーミング"*) return 0 ;; *) return 1 ;; esac; }

# 16. gameable row, no metamorphic, with a source change => the held-out advisory fires.
R="$(mkrepo)"; adopt "$R"
printf 'export const x = 1\n' > "$R/app.ts"
printf 'TODO | gameable | scoring output is easily hardcoded | expected value | ai |\n' > "$R/docs/verification/main.md"
OUT="$(verification_drift_report "$R")"
test_case "gameable-without-metamorphic advisory fires on a populated plan"
if gamed "$OUT"; then assert_eq ok ok; else assert_eq ok FAIL; fi

# 17. gameable row WITH a metamorphic row => silent on the held-out axis (mitigation present).
R="$(mkrepo)"; adopt "$R"
printf 'export const x = 1\n' > "$R/app.ts"
cat > "$R/docs/verification/main.md" <<'EOF'
PASS | gameable     | scoring output is easily hardcoded     | expected value    | ai | flagged
PASS | metamorphic  | perturb input -> score relation holds  | invariant relation| ai | wired
EOF
test_case "gameable WITH a metamorphic mitigation is silent on the held-out axis"
if gamed "$(verification_drift_report "$R")"; then assert_eq ok FAIL; else assert_eq ok ok; fi

# 18. A row whose behaviour text contains 'hardcode'/'game' but NO gameable kind must NOT
#     fire the held-out advisory (the lexicon-scan false-fire, keyed on the kind field only).
R="$(mkrepo)"; adopt "$R"
printf 'export const x = 1\n' > "$R/app.ts"
cat > "$R/docs/verification/main.md" <<'EOF'
PASS | unit | avoid a hardcoded magic number in the game loop | known | ai | ok
DROP | unit | gameable-looking prose but not the kind field   | n/a   | ai | low risk
EOF
test_case "prose containing 'hardcode/game' does NOT fire the held-out advisory"
if gamed "$(verification_drift_report "$R")"; then assert_eq ok FAIL; else assert_eq ok ok; fi

# 19. gameable row but the change is DOC-ONLY => silent (gated on a source-face change).
R="$(mkrepo)"; adopt "$R"
printf '# notes\n' > "$R/README.md"
printf 'TODO | gameable | scoring output is easily hardcoded | expected value | ai |\n' > "$R/docs/verification/main.md"
test_case "held-out advisory is silent on a docs-only branch"
assert_eq "" "$(verification_drift_report "$R")"

# 20. The held-out advisory is ADVISORY: verification_drift_report returns 0 even when it fires.
R="$(mkrepo)"; adopt "$R"
printf 'export const x = 1\n' > "$R/app.ts"
printf 'TODO | gameable | scoring output is easily hardcoded | expected value | ai |\n' > "$R/docs/verification/main.md"
verification_drift_report "$R" >/dev/null 2>&1
test_case "verification_drift_report returns 0 even when the held-out advisory fires"
assert_eq 0 "$?"

finish
