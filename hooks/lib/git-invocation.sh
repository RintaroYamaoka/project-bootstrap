#!/usr/bin/env bash
# Shared, single-authority walker for "does this command invoke `git <subcommand>`?"
# (ADR 0019 — docs/decisions/0019-git-invocation-detection-single-authority.md)
#
# Why this exists (the live bug class, all reproduced in the 2026-07-10 audit): every
# Bash gate answered the question with its own regex —
#   (^|[[:space:]&|;()`]+)git[[:space:]]+commit($|[[:space:]])
# That string proxy requires the subcommand IMMEDIATELY after the word `git`, so it
# missed ALL of these, and the blocking gates fail-OPENed on the very commands they
# exist to block (protected push / test / lint / arch / lane / cross-wip):
#   - git GLOBAL OPTIONS between git and the subcommand:
#       git -C /repo push origin main      (value in the NEXT token)
#       git -c k=v commit -m x
#       git --git-dir=.git push …          (inline value)
#       git -P push … / git --no-pager …   (flag-only)
#   - path-prefixed git on the commit-side gates: /usr/bin/git commit, ./git commit
#     (the push/merge libs already allowed `/`; the commit gates never got the fix).
# Patching the regex per new option is whack-a-mole. This lib tokenizes instead:
# pad shell separators -> word-split under noglob -> find a `git`/`*/git` head ->
# skip git global options (value-takers swallow the NEXT token; any other `-…` token
# before the subcommand is a flag-only global) -> the FIRST non-option token is THE
# subcommand of that invocation. Every segment of a compound command is walked.
#
# Fail-direction of the design: an UNKNOWN `-…` token between git and the subcommand
# is treated as a flag-only global option (git itself would error on it anyway), so
# ambiguity biases toward DETECTION — for blocking gates that is the safe (closed)
# side, never the silent-bypass side.
#
# Known limits (documented, not silent — same as merge-targets.sh/protected-branch.sh;
# both are irreducible without a full shell parser):
#   - quoted SEPARATOR / a `git <sub>` sequence inside a quoted argument: mis-splits
#     toward OVER-detect (a quoted "git commit" in a message arms a gate = fail-closed
#     noise on a blocking gate).
#   - quote/escape on the GIT-HEAD or SUBCOMMAND token itself, a glued redirection, or
#     a nested-shell launcher: `git 'push' …` / `"git" push …` / `\git push …` /
#     `git pu\sh …` / `git push>/dev/null …` / `sh -c "git push …"` tokenize to words
#     this walker does not de-quote/unwrap, so they UNDER-detect (silent pass). This is
#     the same hole the old regexes had (no regression); the commit-time gates and the
#     server-side CI/branch-protection layer (ADR 0012) remain as nets.
# Pure bash, jq-free. sed/grep は排除済み (下記) — hot path は fork ゼロ。
#
# fork ゼロ化 (2026-08-31, Windows 高速化): MSYS/Git Bash は fork が Linux の 10-30 倍
# 遅く、この lib は 12 gate が全 Bash tool call で通る最頻路だった。3 点を変えた:
#   1. 純 builtin の事前ガード — `git` という部分文字列を含まない command は即 no-match。
#      walker が検出できる git 起動は必ず literal token `git` / `*/git` を含む (= 部分
#      文字列 `git` を含む) ので、このガードで検出集合は 1 ミリも狭まらない。quoted
#      git-head (`"git" push`) 等は元々 walker too が under-detect する既知の既約残余。
#   2. separator padding を sed から純 bash の ${var//} 置換に (\x01/\x02 を && / || の
#      sentinel に使い、万一 command 自体が制御文字を含む稀ケースだけ sed に fallback)。
#   3. 存在判定を `| grep -q ''` (pipeline 2 fork + grep exec) からカウンタ変数に。

# Include guard — dispatcher が 1 プロセスに複数 gate を source するときの再読込抑止。
[ -n "${_BOOTSTRAP_LIB_GIT_INVOCATION:-}" ] && return 0
_BOOTSTRAP_LIB_GIT_INVOCATION=1

# _git_gopt_takes_value <tok> — return 0 if <tok> is a git GLOBAL option whose value
# is the NEXT token (git accepts the space-separated form for these). Inline `=`
# forms (--git-dir=…) carry their value in the same token and fall to the generic
# flag-only arm in the walker. --exec-path/--html-path & friends never take a
# separate-token value, so they are deliberately NOT listed.
_git_gopt_takes_value() {
  case "$1" in
    -C|-c|--git-dir|--work-tree|--namespace|--config-env|--attr-source) return 0 ;;
    *) return 1 ;;
  esac
}

# _git_pad_separators <cmd> — shell separator (incl. subshell parens / backtick) の
# 前後に空白を入れた文字列を GIT_PADDED_CMD に set する (fork ゼロ)。&& と || は単位で
# pad する (sed の leftmost-longest と同じ) ため、先に sentinel (\x01 / \x02) へ退避
# してから単独 & / | を pad する。command 自体が sentinel の制御文字を含む稀ケースは
# 置換が壊れるので従来の sed 経路に fallback する (正しさ優先 — 頻度は実質ゼロ)。
_git_pad_separators() {
  local s="$1" a=$'\001' b=$'\002'
  case "$s" in
    *"$a"*|*"$b"*)
      GIT_PADDED_CMD="$(printf '%s' "$s" | sed -E 's/(\&\&|\|\||;|\||\&|\(|\)|`)/ & /g')"
      return 0 ;;
  esac
  # 置換文字列に `&` を置かない (bash 5.2 の patsub_replacement は無引用の & をマッチ
  # 文字列に展開し、bash 3.2 は \& を literal \& にする — 版で挙動が割れる)。&& / || は
  # sentinel トークンのまま残し、walker 側が separator として読む (下の case 参照)。
  s="${s//&&/ $a }"
  s="${s//||/ $b }"
  s="${s//;/ ; }"
  s="${s//|/ | }"
  s="${s//&/ $a }"
  s="${s//(/ ( }"
  s="${s//)/ ) }"
  s="${s//\`/ \` }"
  GIT_PADDED_CMD="$s"
}

# _git_walk <cmd> <sub> <emit> — the single walker body. emit=print で従来の argline
# 出力、emit=count で出力なし。どちらの mode でも GIT_SUB_MATCHES にマッチ segment 数を
# set する (単一権威を保ったまま存在判定を fork ゼロにするための二重出口)。
_git_walk() {
  local cmd="$1" sub="$2" emit="$3" tok noglob=0 in_git=0 skip_next=0 collecting=0 acc=""
  local a=$'\001' b=$'\002'   # _git_pad_separators の sentinel separator token
  GIT_SUB_MATCHES=0
  # 純 builtin の事前ガード (fork ゼロ化 #1 — header 参照): literal token `git`/`*/git`
  # を含み得ない command はここで打ち切る。検出集合は不変 (部分文字列 `git` は必要条件)。
  case "$cmd" in *git*) ;; *) return 0 ;; esac
  # Pad shell separators so they tokenize as standalone words even when written
  # without surrounding spaces (git stash;git stash).
  _git_pad_separators "$cmd"
  # noglob during word-splitting so a token containing * or ? is not expanded against
  # the filesystem (which could drop or mangle a token = fail-open).
  case $- in *f*) ;; *) noglob=1; set -f ;; esac
  # shellcheck disable=SC2086
  set -- $GIT_PADDED_CMD
  while [ $# -gt 0 ]; do
    tok="$1"; shift
    case "$tok" in
      '&&'|'||'|';'|'|'|'&'|'('|')'|'`'|"$a"|"$b")
        if [ "$collecting" = 1 ]; then
          GIT_SUB_MATCHES=$((GIT_SUB_MATCHES + 1))
          [ "$emit" = print ] && printf '%s\n' "$acc"
        fi
        in_git=0; skip_next=0; collecting=0; acc=""
        continue ;;
    esac
    if [ "$collecting" = 1 ]; then
      if [ -z "$acc" ]; then acc="$tok"; else acc="$acc $tok"; fi
      continue
    fi
    if [ "$in_git" = 1 ]; then
      if [ "$skip_next" = 1 ]; then skip_next=0; continue; fi
      case "$tok" in
        -*)
          # a git GLOBAL option before the subcommand; value-takers swallow the next token
          _git_gopt_takes_value "$tok" && skip_next=1
          continue ;;
      esac
      # first non-option token after `git` = THE subcommand of this invocation
      if [ "$tok" = "$sub" ]; then
        collecting=1; acc=""
      else
        in_git=0
      fi
      continue
    fi
    case "$tok" in
      git|*/git) in_git=1; skip_next=0 ;;
    esac
  done
  if [ "$collecting" = 1 ]; then
    GIT_SUB_MATCHES=$((GIT_SUB_MATCHES + 1))
    [ "$emit" = print ] && printf '%s\n' "$acc"
  fi
  [ "$noglob" = 1 ] && set +f
  return 0
}

# git_subcommand_arglines <cmd> <sub> — for EVERY segment of a (possibly compound)
# command that invokes `git <sub>`, print ONE line: the segment's remaining tokens
# joined by single spaces. An argument-less invocation prints an EMPTY line (the
# segment still counts). No matching segment prints nothing at all.
# Git global options are consumed BEFORE the subcommand and never appear in a line.
git_subcommand_arglines() {
  _git_walk "$1" "$2" print
}

# cmd_invokes_git_subcommand <cmd> <sub> — return 0 if ANY segment of the command
# invokes `git <sub>` (path-prefixed git and git global options included).
# fork ゼロ (走査は current process、stdout には何も出ない)。
cmd_invokes_git_subcommand() {
  _git_walk "$1" "$2" count
  [ "$GIT_SUB_MATCHES" -gt 0 ]
}
