#!/usr/bin/env bash
# Tests for hooks/block-cross-claude-wip.sh
#
# Regression origin: a real parallel-dev incident. Two Claude terminals shared one
# working tree (= one .git/index). Terminal B's `git commit --amend` swept Terminal A's
# 14 staged files (docs + tests) into commit 67c2bad with the wrong message, which was
# then pushed to origin/main. The hook DID block plain `git commit` of foreign staged
# files, but block-cross-claude-wip.sh exempted `--amend` entirely — that exemption was
# the hole. These tests pin the fix and guard against over-blocking message-only amend.

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"

# setup_repo — fresh temp git repo with one seed commit. Sets REPO to git's own
# toplevel view so that paths in the fake transcript share git's path prefix
# (avoids msys /tmp vs C:/.../Temp mismatch on Windows).
setup_repo() {
  local tmp; tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  REPO="$(git -C "$tmp" rev-parse --show-toplevel)"
  git -C "$REPO" config user.email t@t.test
  git -C "$REPO" config user.name tester
  echo seed > "$REPO/seed.txt"
  git -C "$REPO" add seed.txt
  git -C "$REPO" commit -qm seed
}

# make_transcript <self-edited-path>... — the CURRENT session's JSONL transcript,
# placed in a fresh per-test transcript dir that mirrors ~/.claude/projects/<hash>/.
# Sibling session transcripts (= other terminals sharing this working tree) go in the
# SAME dir via make_foreign_transcript. Edit tool_use entries declare the given files
# as edited by "this session".
FOREIGN_N=0
make_transcript() {
  TS_DIR="$(mktemp -d)"
  FOREIGN_N=0
  TRANSCRIPT="$TS_DIR/current.jsonl"
  : > "$TRANSCRIPT"
  local p
  for p in "$@"; do
    printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"%s"}}]}}\n' "$p" >> "$TRANSCRIPT"
  done
}

# make_foreign_transcript <edited-path>... — a sibling session transcript in the SAME
# projects dir, modeling another Claude terminal that shares this working tree (= shared
# .git/index). Its declared files are what the new hook treats as "foreign-edited".
# Returns the path so callers can backdate its mtime (recency-window tests).
make_foreign_transcript() {
  FOREIGN_N=$((FOREIGN_N + 1))
  local f="$TS_DIR/foreign-$FOREIGN_N.jsonl"
  : > "$f"
  local p
  for p in "$@"; do
    printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"%s"}}]}}\n' "$p" >> "$f"
  done
  printf '%s\n' "$f"
}

# add_self_staged <command> — 当 session の transcript に Bash tool_use を1件足す。
# 「当 session が自分で stage した」証跡をつくるために使う。
add_self_staged() {
  printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"%s"}}]}}\n' "$1" >> "$TRANSCRIPT"
}

# input_json <command> <transcript-path> <cwd>
input_json() {
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"transcript_path":"%s","cwd":"%s"}' "$1" "$2" "$3"
}

# 1. The incident itself: --amend with a foreign file in the shared index must block.
#    "Foreign" now means: a sibling session (another terminal sharing this tree) edited it.
setup_repo
echo foreign > "$REPO/foreign.txt"
git -C "$REPO" add foreign.txt          # staged by "another session", NOT self-edited
make_transcript "$REPO/mine.txt"         # this session only touched mine.txt
make_foreign_transcript "$REPO/foreign.txt" >/dev/null   # the other terminal edited foreign.txt
RUN_DIR="$REPO"
test_case "amend with foreign staged file is blocked"
run_hook block-cross-claude-wip.sh "$(input_json 'git commit --amend -m x' "$TRANSCRIPT" "$REPO")"
assert_exit 2

# 2. Do not over-block: message-only amend (clean index) must pass.
setup_repo
make_transcript "$REPO/mine.txt"
RUN_DIR="$REPO"
test_case "amend with clean index (message-only) passes"
run_hook block-cross-claude-wip.sh "$(input_json 'git commit --amend -m newmsg' "$TRANSCRIPT" "$REPO")"
assert_exit 0

# 3. Regression guard: plain commit of a foreign staged file still blocks.
setup_repo
echo foreign > "$REPO/foreign.txt"
git -C "$REPO" add foreign.txt
make_transcript "$REPO/mine.txt"
make_foreign_transcript "$REPO/foreign.txt" >/dev/null
RUN_DIR="$REPO"
test_case "plain commit with foreign staged file is blocked"
run_hook block-cross-claude-wip.sh "$(input_json 'git commit -m x' "$TRANSCRIPT" "$REPO")"
assert_exit 2

# 4. Commit of only self-edited files passes.
setup_repo
echo mine > "$REPO/mine.txt"
git -C "$REPO" add mine.txt
make_transcript "$REPO/mine.txt"
RUN_DIR="$REPO"
test_case "commit of only self-edited file passes"
run_hook block-cross-claude-wip.sh "$(input_json 'git commit -m x' "$TRANSCRIPT" "$REPO")"
assert_exit 0

# 5. BUG FIX regression: a same-session Bash artifact (e.g. npm install's lockfile) is
#    staged but appears in NO session's edit-tool set. The old impl flagged it as an
#    intruder (Bash leaves no file_path); the fix must let it through — there is no
#    evidence another session touched it.
setup_repo
echo '{}' > "$REPO/package-lock.json"   # produced by `npm install` via the Bash tool
git -C "$REPO" add package-lock.json
make_transcript "$REPO/src/index.ts"     # this session only Edit'd source, never the lockfile
RUN_DIR="$REPO"
test_case "same-session Bash artifact (lockfile) passes"
run_hook block-cross-claude-wip.sh "$(input_json 'git commit -m x' "$TRANSCRIPT" "$REPO")"
assert_exit 0

# 6. fail-open: a staged file not attributable to any session (no sibling transcripts at
#    all) passes. Absence of evidence is not treated as guilt.
setup_repo
echo gen > "$REPO/generated.txt"         # output of a generator script run via Bash
git -C "$REPO" add generated.txt
make_transcript "$REPO/mine.txt"
RUN_DIR="$REPO"
test_case "staged file with no owning session (no siblings) passes (fail-open)"
run_hook block-cross-claude-wip.sh "$(input_json 'git commit -m x' "$TRANSCRIPT" "$REPO")"
assert_exit 0

# 7. Recency window: a sibling transcript older than the window is ignored, so a file it
#    edited is not blocked (avoids stale-session false positives).
setup_repo
echo foreign > "$REPO/foreign.txt"
git -C "$REPO" add foreign.txt
make_transcript "$REPO/mine.txt"
STALE="$(make_foreign_transcript "$REPO/foreign.txt")"
touch -t 202001010000 "$STALE"           # backdate well outside the default 24h window
RUN_DIR="$REPO"
test_case "stale sibling beyond window is ignored (file passes)"
run_hook block-cross-claude-wip.sh "$(input_json 'git commit -m x' "$TRANSCRIPT" "$REPO")"
assert_exit 0

# 8. Window disabled: with BOOTSTRAP_WIP_WINDOW_HOURS=0 even an old sibling counts, so the
#    same stale-sibling file blocks again. Pins the env override.
setup_repo
echo foreign > "$REPO/foreign.txt"
git -C "$REPO" add foreign.txt
make_transcript "$REPO/mine.txt"
STALE="$(make_foreign_transcript "$REPO/foreign.txt")"
touch -t 202001010000 "$STALE"
RUN_DIR="$REPO"
test_case "window disabled (=0) counts stale sibling, file blocks"
BOOTSTRAP_WIP_WINDOW_HOURS=0 run_hook block-cross-claude-wip.sh "$(input_json 'git commit -m x' "$TRANSCRIPT" "$REPO")"
assert_exit 2

# 9. Detector bypasses (2026-07-10 audit): a foreign staged file proves detection —
#    exit 2 == the gate saw the commit despite the path prefix / global option.
setup_repo
echo foreign > "$REPO/foreign.txt"
git -C "$REPO" add foreign.txt
make_transcript "$REPO/mine.txt"
make_foreign_transcript "$REPO/foreign.txt" >/dev/null
RUN_DIR="$REPO"
test_case "/usr/bin/git commit is detected and gated (path-prefix bypass)"
run_hook block-cross-claude-wip.sh "$(input_json '/usr/bin/git commit -m x' "$TRANSCRIPT" "$REPO")"
assert_exit 2

test_case "git -C <path> commit is detected and gated (global-option bypass)"
run_hook block-cross-claude-wip.sh "$(input_json 'git -C . commit -m x' "$TRANSCRIPT" "$REPO")"
assert_exit 2

# 10. A file THIS session staged by name is its own choice, not a sweep.
#     実例: 終了済みの別 session が過去にそのファイルを編集していたが、その編集は既に
#     commit 済み / 取り消し済みで working tree には残っていない。それでも旧実装は
#     「他 session が触った file」というだけで intruder 扱いし、当 session が自分で書いて
#     自分で `git add <path>` した file の commit を止めていた (誤検知)。
#     巻き込み事故の本体は「自分が選んでいない file が index に居る」ことなので、
#     path を名指しで staged した file は self として扱う。
setup_repo
echo shared > "$REPO/shared.txt"
git -C "$REPO" add shared.txt
make_transcript "$REPO/mine.txt"          # 編集ツールでは触っていない (Bash 経由で書いた file)
add_self_staged "git add shared.txt"      # だが当 session が名指しで stage した
make_foreign_transcript "$REPO/shared.txt" >/dev/null   # 別 session も過去に編集していた
RUN_DIR="$REPO"
test_case "file this session staged by name passes even if a sibling once edited it"
run_hook block-cross-claude-wip.sh "$(input_json 'git commit -m x' "$TRANSCRIPT" "$REPO")"
assert_exit 0

# 11. 逆に、bulk staging は path を名指ししないので self にならない — 事故の本体を守る。
#     (別 terminal の bulk stage が他 session の WIP を index に入れた、という経路)
setup_repo
echo foreign > "$REPO/foreign.txt"
git -C "$REPO" add foreign.txt
make_transcript "$REPO/mine.txt"
add_self_staged "git add -A"
make_foreign_transcript "$REPO/foreign.txt" >/dev/null
RUN_DIR="$REPO"
test_case "bulk staging does not make a foreign file self-staged"
run_hook block-cross-claude-wip.sh "$(input_json 'git commit -m x' "$TRANSCRIPT" "$REPO")"
assert_exit 2

# 12. `git add` を含まないコマンドで path に触れただけでは self にならない
#     (例: 読んだだけの file を自分のものにしない)
setup_repo
echo foreign > "$REPO/foreign.txt"
git -C "$REPO" add foreign.txt
make_transcript "$REPO/mine.txt"
add_self_staged "cat foreign.txt"
make_foreign_transcript "$REPO/foreign.txt" >/dev/null
RUN_DIR="$REPO"
test_case "merely reading a path does not make it self-staged"
run_hook block-cross-claude-wip.sh "$(input_json 'git commit -m x' "$TRANSCRIPT" "$REPO")"
assert_exit 2

# 13. 実際に踏んだ誤検知: transcript の command は複数行を JSON の \n で持つ。
#     `cd repo\ngit add path` のように \n の直後に git が来ると、境界を「英数字でない文字」
#     で判定していた旧パターンは n を英数字と見て弾き、self-staged を取りこぼした。
setup_repo
echo shared > "$REPO/shared.txt"
git -C "$REPO" add shared.txt
make_transcript "$REPO/mine.txt"
add_self_staged "cd /somewhere\\ngit add shared.txt\\ngit status"
make_foreign_transcript "$REPO/shared.txt" >/dev/null
RUN_DIR="$REPO"
test_case "git add after an escaped newline still counts as self-staged"
run_hook block-cross-claude-wip.sh "$(input_json 'git commit -m x' "$TRANSCRIPT" "$REPO")"
assert_exit 0

# 14. `git -C <dir> add <path>` も self-staged として数える (値つきグローバルオプション)
setup_repo
echo shared > "$REPO/shared.txt"
git -C "$REPO" add shared.txt
make_transcript "$REPO/mine.txt"
add_self_staged "git -C . add shared.txt"
make_foreign_transcript "$REPO/shared.txt" >/dev/null
RUN_DIR="$REPO"
test_case "git -C <dir> add <path> counts as self-staged"
run_hook block-cross-claude-wip.sh "$(input_json 'git commit -m x' "$TRANSCRIPT" "$REPO")"
assert_exit 0

finish
