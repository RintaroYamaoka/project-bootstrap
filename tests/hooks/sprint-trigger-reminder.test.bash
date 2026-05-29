#!/usr/bin/env bash
# Tests for hooks/sprint-trigger-reminder.sh
#
# Why this hook exists: sprint auto-decomposition is an advisory in SKILL.md (Claude must
# self-trigger from exploration). When SKILL drops out of context it silently never fires —
# the exact "advisory is forgotten" failure mode the plugin rejects elsewhere. This hook
# deterministically re-injects the 3-point trigger checklist on feature-ish prompts so the
# decision is never skipped. It does NOT (and cannot) launch a sprint itself.

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"

# prompt_json <prompt-text>
prompt_json() {
  printf '{"hook_event_name":"UserPromptSubmit","prompt":"%s","cwd":"/tmp/x"}' "$1"
}

# 1. A feature-implementation prompt injects the checklist as UserPromptSubmit context.
test_case "feature prompt injects the sprint checklist"
run_hook sprint-trigger-reminder.sh "$(prompt_json 'ユーザー認証の機能を実装してほしい')"
assert_exit 0
assert_stdout_contains '"hookEventName":"UserPromptSubmit"'
assert_stdout_contains 'additionalContext'
assert_stdout_contains 'sprint'

# 2. Explicit parallel/scrum request also fires.
test_case "explicit 並列で request fires"
run_hook sprint-trigger-reminder.sh "$(prompt_json 'この機能を並列で進めて')"
assert_exit 0
assert_stdout_contains 'additionalContext'

# 3. A non-feature prompt (typo fix) stays silent — no context noise.
test_case "typo-fix prompt is silent"
run_hook sprint-trigger-reminder.sh "$(prompt_json 'READMEのこのtypoを直して')"
assert_exit 0
assert_stdout_empty

# 4. A pure question stays silent.
test_case "plain question is silent"
run_hook sprint-trigger-reminder.sh "$(prompt_json 'このリポジトリの構成を教えて')"
assert_exit 0
assert_stdout_empty

# 5. The injected JSON carries the 3 gate conditions (① feature / ② disjoint leaf / ③ wip_limit).
test_case "checklist names the three gate conditions"
run_hook sprint-trigger-reminder.sh "$(prompt_json 'ダッシュボード機能を新規実装したい')"
assert_stdout_contains 'wip_limit'
assert_stdout_contains 'leaf'

finish
