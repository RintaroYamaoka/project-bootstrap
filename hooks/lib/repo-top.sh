#!/usr/bin/env bash
# repo_top_var — 現在 cwd の git worktree root を正規化済み (backslash → slash、
# 連続 slash squeeze = norm_path_var と同一規則) で REPO_TOP に set する。
# git 不在 / repo 外なら REPO_TOP は空 (呼び手が fail-open を選ぶ従来挙動のまま)。
#
# WHY (ADR 0026): 従来はほぼ全 gate が各自
#   git rev-parse --show-toplevel 2>/dev/null | tr '\\' '/' | tr -s '/'
# を払っていた (プロセス 4 つ)。dispatcher が 22 gate を 1 プロセスで回す現在、これは
# 1 tool call に同じ質問を最大 10 回聞く形になる。cwd は 1 回の hook 呼び出しの間
# 不変なので、プロセス内 memo で 1 回に潰す (fork は初回の 1 回だけ)。
#
# 依存: lib/parse-command.sh (norm_path_var)。

[ -n "${_BOOTSTRAP_LIB_REPO_TOP:-}" ] && return 0
_BOOTSTRAP_LIB_REPO_TOP=1

repo_top_var() {
  if [ -n "${_BOOTSTRAP_REPO_TOP_SET:-}" ]; then
    REPO_TOP="$_BOOTSTRAP_REPO_TOP"
    return 0
  fi
  REPO_TOP=""
  if command -v git >/dev/null 2>&1; then
    local t
    t="$(git rev-parse --show-toplevel 2>/dev/null)" || t=""
    if [ -n "$t" ]; then
      norm_path_var "$t"
      REPO_TOP="$NORM_PATH"
    fi
  fi
  _BOOTSTRAP_REPO_TOP="$REPO_TOP"
  _BOOTSTRAP_REPO_TOP_SET=1
}
