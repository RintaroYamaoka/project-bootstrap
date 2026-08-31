#!/usr/bin/env bash
# Shared, fail-closed extractor for string fields of the hook's stdin JSON payload.
#
# Every PreToolUse-on-Bash hook needs the `command` value out of the JSON payload
# Claude Code pipes on stdin, and the Edit/SessionStart hooks need `file_path` /
# `cwd` / `transcript_path`. The hooks used to do:
#   grep -oE '"command"[^,}]*'
# but `[^,}]*` stops at the first ',' or '}', so a command containing either —
#   git commit -m "fix, bug" && git add -A
# — was truncated to `git commit -m "fix`, dropping the trailing `git add -A`. The
# gates (block-add-all, block-dangerous-git-ops, …) then saw a harmless fragment
# and passed (fail-OPEN) commands they exist to block: the exact "silent failure /
# falls to the unsafe side" trap the discipline warns about. The 2026-07-10 audit
# found the SAME truncation pattern still live at eight call sites for file_path /
# cwd / transcript_path (a path containing ',' '}' or an escaped quote was cut
# mid-value and those gates silently fail-OPENed), so the extractor is generalized:
# parse_json_string_field <key> is the single authority for pulling any string
# field out of the payload; parse_command is its `command` alias.
#
# parse_json_string_field reads to the real (unescaped) closing quote and decodes
# one level of JSON string escapes, so commas, braces and embedded quotes are
# handled. When the input is unparseable it returns non-zero AND prints nothing, so
# each caller chooses its fail-mode (blocking gates fail CLOSED on `command`;
# advisory/visibility callers fail OPEN). Pure bash, jq-free — matches lib/arch-check.sh.
#
# Contract (parse_json_string_field <key>):
#   stdin  : raw hook JSON
#   stdout : decoded value of the first "<key>" key
#   return : 0 if the key was found (value may be empty); 1 if absent/unterminated.
#
# Note: \uXXXX is left undecoded (rare in shell commands/paths); every other JSON
# escape (\" \\ \/ \n \t \r \b \f) is decoded. The single left-to-right scan also
# resolves the \\" ambiguity correctly (\\ then ", not \ then escaped-quote).

# Include guard — dispatcher が 1 プロセスに複数 gate を source するとき、同じ lib の
# 再読込 (open+parse の I/O — Windows で高くつく) を 1 回に抑える。
[ -n "${_BOOTSTRAP_LIB_PARSE_COMMAND:-}" ] && return 0
_BOOTSTRAP_LIB_PARSE_COMMAND=1

# ── fork ゼロの変数ベース API (dispatcher の hot path 用)
#
# Windows (Git Bash / MSYS) は fork が Linux の 10-30 倍遅く、hook の体感遅延の主因は
# サブプロセス数そのもの。dispatcher (hooks/dispatch.sh) は stdin を builtin read で
# 1 回だけ読み、以下の変数ベース関数でサブプロセスなしに field を取り出す。
# 単一権威は json_field_var — stdin 版 (parse_json_string_field / parse_command) は
# その thin wrapper (二経路に同じ穴を作らない)。
#
# 契約:
#   json_field_var <key> <json>  : 成功 = JSON_FIELD を set して return 0
#                                  失敗 (key 不在 / 未終端) = return 1 (JSON_FIELD は空)
#   parse_command_var <json>     : PARSED_CMD に heredoc 本文除去済みの command を set。
#                                  return は json_field_var と同じ fail 契約。

# json_field_var <key> <json> — see above. Pure bash, no subprocess.
json_field_var() {
  local key="$1" input="$2" after c nxt out="" i len
  JSON_FIELD=""

  # Locate the first "<key>" occurrence. No occurrence => unparseable (caller decides).
  case "$input" in
    *"\"$key\""*) ;;
    *) return 1 ;;
  esac
  after="${input#*\"$key\"}"

  # Skip whitespace, the ':', more whitespace, then require the opening quote.
  after="${after#"${after%%[![:space:]]*}"}"
  [ "${after:0:1}" = ":" ] || return 1
  after="${after:1}"
  after="${after#"${after%%[![:space:]]*}"}"
  [ "${after:0:1}" = '"' ] || return 1
  after="${after:1}"

  # Scan the value char-by-char to the first UNESCAPED '"', decoding as we go.
  len=${#after}
  i=0
  while [ "$i" -lt "$len" ]; do
    c="${after:i:1}"
    if [ "$c" = "\\" ]; then
      nxt="${after:i+1:1}"
      case "$nxt" in
        '"') out="$out\"" ;;
        '\') out="$out\\" ;;
        '/') out="$out/" ;;
        n)   out="$out"$'\n' ;;
        t)   out="$out"$'\t' ;;
        r)   out="$out"$'\r' ;;
        b)   out="$out"$'\b' ;;
        f)   out="$out"$'\f' ;;
        '')  out="$out\\"; i=$((i + 1)); continue ;;  # trailing lone backslash
        *)   out="$out\\$nxt" ;;                        # unknown escape: keep both
      esac
      i=$((i + 2))
      continue
    fi
    if [ "$c" = '"' ]; then
      JSON_FIELD="$out"
      return 0
    fi
    out="$out$c"
    i=$((i + 1))
  done

  # Reached end of input without a closing quote => unterminated (fail-closed).
  return 1
}

# edit_file_var <json> — Edit|Write|MultiEdit payload から編集対象 path を FILE に set
# する (file_path が無い / 空なら path に fallback — 全 Edit gate が共有していた入口の
# 単一権威化)。どちらも取れなければ FILE は空 (= 各 gate は fail-open で素通し)。
# fork ゼロ。常に return 0 (fail-mode は呼び手が FILE の空で判断する)。
edit_file_var() {
  FILE=""
  json_field_var file_path "$1" || JSON_FIELD=""
  FILE="$JSON_FIELD"
  if [ -z "$FILE" ]; then
    json_field_var path "$1" || JSON_FIELD=""
    FILE="$JSON_FIELD"
  fi
  return 0
}

# norm_path_var <path> — Windows 対応の path 正規化 (backslash → slash、連続 slash の
# squeeze) を NORM_PATH に set する。従来 gate ごとに `tr '\\' '/' | tr -s '/'` (pipeline
# 2 fork + tr exec ×2) を払っていたのを fork ゼロにした単一権威。
norm_path_var() {
  local s="$1"
  s="${s//\\//}"
  while :; do
    case "$s" in
      *//*) s="${s//\/\//\/}" ;;
      *) break ;;
    esac
  done
  # shellcheck disable=SC2034  # cross-file return channel (呼び手が読む)
  NORM_PATH="$s"
}

# parse_json_string_field <key> — stdin wrapper over json_field_var (see file header
# for the original contract: reads raw hook JSON on stdin, writes the decoded value
# to stdout, rc 0 = found / 1 = absent-or-unterminated). Costs one $(cat) fork —
# hot-path callers (dispatch.sh) use json_field_var directly instead.
parse_json_string_field() {
  json_field_var "$1" "$(cat)" || return 1
  printf '%s' "$JSON_FIELD"
}

# ── heredoc 本文の除去 (ADR 0025 — ai-reception 2026-08-08 の誤検知 incident)
#
# 問題: gate は「コマンド文字列」を走査するが、heredoc 本文は**実行されるコマンドでは
# なく stdin に渡されるデータ**である。walker (lib/git-invocation.sh) は改行を単なる
# 空白として word-split するので本文のトークンがコマンド列に流れ込み、raw regex 経路
# (block-dangerous-git-ops) も同様に本文の字面を拾う。結果、
#   git commit -F - <<'MSG' … 一括 stage は `git add -A` を使わない … MSG
# のような **規約の説明を書いた commit 自身が block された**。
# これは ② 信号選び (gate は proxy でなく行為そのものを信号にする) の違反で、
# 「テキストの字面」という proxy を行為と誤読していた。false positive は安全側に
# 見えるが、**規律を回避する動機を作る** (実際 hook を deny にする案が出た) ため、
# 「塞ぐ」と「塞がれても困らなくする」を対で設計する原則に従い除去する。
#
# fail-direction: 本文を落とすのは検出を**緩める**向きなので、**本文が実際に実行される
# 形は落とさない** — `bash <<EOF … EOF` は本文がシェルに食われて実行されるので、
# その行の heredoc は本文ごと gate の視界に残す (fail-closed を維持)。
#
# 射程外 (既知・無音にしない): quoted 引数の中の字面 (`-m "… git add -A …"`) は
# 依然 over-detect する。quote 剥がしは引数の値を消すので、pathspec を引数から取る
# 消費者 (lib/commit-files.sh 等) を無音で壊す危険があり、別途扱う (ADR 0025)。

# _heredoc_exec_line <line> — この行が heredoc を「実行する側」に食わせているなら 0。
# シェル / eval に渡る本文はコマンドそのものなので、除去の対象にしない。
_heredoc_exec_line() {
  local line="$1" tok rc=1 noglob=0
  case $- in *f*) ;; *) noglob=1; set -f ;; esac
  # shellcheck disable=SC2086
  set -- $line
  while [ $# -gt 0 ]; do
    tok="$1"; shift
    case "$tok" in
      sh|bash|zsh|dash|ksh|eval|source|.|*/sh|*/bash|*/zsh|*/dash|*/ksh) rc=0; break ;;
    esac
  done
  [ "$noglob" = 1 ] && set +f
  return $rc
}

# _heredoc_labels <line> — この行が開く heredoc を、開いた順に `<dash>\t<label>` で出力。
# `<<-` は終端ラベルの行頭タブ除去を許す形なので dash=1 として区別する。
# `<<<` (herestring) は本文を持たないので heredoc として数えない。
_heredoc_labels() {
  local rest="$1" tail c dash lbl
  while :; do
    case "$rest" in *'<<'*) ;; *) return 0 ;; esac
    tail="${rest#*<<}"
    rest="$tail"
    # `<<<` (herestring) は本文を持たない。なお下のラベル走査も `<` を語頭に許さないので
    # この行を消しても現挙動は変わらない (mutation で生存を確認済み = 二重の防御であり
    # 単独では load-bearing でない)。ラベル走査を将来変えたときの保険として残す。
    case "$tail" in '<'*) continue ;; esac
    dash=0
    case "$tail" in '-'*) dash=1; tail="${tail#-}" ;; esac
    tail="${tail#"${tail%%[![:space:]]*}"}"
    # ラベルは quote / backslash で囲めるが、展開の有無だけの違いで名前は同じ
    case "$tail" in
      "'"*) tail="${tail#\'}" ;;
      '"'*) tail="${tail#\"}" ;;
      '\'*) tail="${tail#\\}" ;;
    esac
    lbl=""
    while [ -n "$tail" ]; do
      c="${tail:0:1}"
      case "$c" in
        [A-Za-z0-9_]) lbl="$lbl$c"; tail="${tail:1}" ;;
        *) break ;;
      esac
    done
    [ -n "$lbl" ] && printf '%s\t%s\n' "$dash" "$lbl"
  done
}

# strip_heredoc_bodies <cmd> — heredoc の本文と終端ラベル行を落とし、演算子行 (= 実際の
# コマンド) と本文の外にある行は保持する。終端ラベルが来ないまま入力が尽きたら、そこまで
# 全部が本文 (シェルもそう解釈する)。pending は「まだ閉じていない heredoc」の待ち行列で、
# 配列を使わず改行区切り文字列で持つ (空配列 + set -u の bash 版依存を避ける)。
strip_heredoc_bodies() {
  local cmd="$1"
  case "$cmd" in *'<<'*) ;; *) printf '%s' "$cmd"; return 0 ;; esac

  local out="" first=1 line t labels pending="" head rest
  while IFS= read -r line || [ -n "$line" ]; do
    if [ -n "$pending" ]; then
      head="${pending%%$'\n'*}"
      t="$line"
      if [ "${head%%$'\t'*}" = 1 ]; then
        while [ "${t:0:1}" = $'\t' ]; do t="${t:1}"; done
      fi
      if [ "$t" = "${head#*$'\t'}" ]; then
        rest="${pending#*$'\n'}"
        [ "$rest" = "$pending" ] && rest=""   # 1 件だけだった
        pending="$rest"
      fi
      continue                                 # 本文行も終端行も落とす
    fi
    if [ "$first" = 1 ]; then out="$line"; first=0; else out="$out"$'\n'"$line"; fi
    _heredoc_exec_line "$line" && continue     # 実行される本文は残す
    labels="$(_heredoc_labels "$line")"
    if [ -n "$labels" ]; then
      if [ -z "$pending" ]; then pending="$labels"; else pending="$pending"$'\n'"$labels"; fi
    fi
  done <<< "$cmd"
  printf '%s' "$out"
}

# parse_command_var <json> — fork ゼロの `command` 抽出 (dispatcher の hot path)。
# PARSED_CMD に heredoc 本文除去済みの command を set する。heredoc が無い (= ほぼ全
# ケース) は純 bash で完結し、heredoc がある稀なケースだけ strip_heredoc_bodies の
# command substitution を払う。
parse_command_var() {
  PARSED_CMD=""
  json_field_var command "$1" || return 1
  case "$JSON_FIELD" in
    *'<<'*) PARSED_CMD="$(strip_heredoc_bodies "$JSON_FIELD")" ;;
    *)      PARSED_CMD="$JSON_FIELD" ;;
  esac
}

# parse_command — the `command` alias (kept as the blocking gates' entry point so the
# fail-closed contract reads at the call site). heredoc 本文はここで落とすので、
# 全 gate が経路 (token walker / raw regex) を問わず同じ「実行されるコマンド」を見る。
# stdin wrapper — 単一権威は parse_command_var。
parse_command() {
  parse_command_var "$(cat)" || return 1
  printf '%s' "$PARSED_CMD"
}
