#!/usr/bin/env bash
# lint gate を「この commit が運ぶ file」に絞り込むためのエンジン。
#
# なぜ要るか (marketing-app 2026-07-09 incident M5 / ADR 0018):
#   lint gate はツリー全体を lint していた。lane worktree にも repo の全 file が複製されるので、
#   lane worker は **自分が所有しない file の lint debt** で commit を止められる。lane の中に正当な
#   remedy が無いので、worker は lane を出て直しに行く (= 実際に `biome format --write` で lane 外を
#   書き換えた)。gate が違反の動機を作っていた。
#
#   信号は **判定対象そのもの** = この commit が運ぶ file であるべきで、ツリー全体ではない。
#
# ただし全 linter が file 引数を取れるわけではない (go/cargo は package 単位)。取れないものは
# 従来どおりツリー全体で fail-closed のまま残す (= 緩めない。scope できる所だけ正確にする)。
#
# lint_script_tool "<npm lint script>"  → 既知の path 対応 tool 名 (無ければ空)
# lint_scoped_base "<npm lint script>"  → その tool を file 引数つきで呼ぶ base command (無ければ空)
# lint_ext_ok <tool> <file>             → その tool が扱う拡張子なら 0

# npm script の先頭トークンから tool を取る。`npx foo` / `pnpm exec foo` / `yarn foo` / `bunx foo`
# のような runner 前置きは剥がす。安全側: 既知の tool だけを path 対応と認める (`next lint` の
# ように file 引数で挙動が変わるものを誤って scope すると、存在しない lint fail を作る)。
# Include guard — dispatcher が 1 プロセスに複数 gate を source するときの再読込抑止。
[ -n "${_BOOTSTRAP_LIB_LINT_SCOPE:-}" ] && return 0
_BOOTSTRAP_LIB_LINT_SCOPE=1

lint_script_tool() {
  local script="$1" tok
  # runner 前置きを剥がす (複数回)
  while :; do
    tok=$(printf '%s' "$script" | awk '{print $1}')
    case "$tok" in
      npx|bunx|pnpm|yarn|npm) script=$(printf '%s' "$script" | cut -d' ' -f2-) ;;
      exec|run|--no-install|--no|-s|--silent) script=$(printf '%s' "$script" | cut -d' ' -f2-) ;;
      *) break ;;
    esac
    [ -n "$script" ] || break
  done
  tok=$(printf '%s' "$script" | awk '{print $1}')
  tok="${tok##*/}"
  case "$tok" in
    eslint|biome|oxlint|prettier) printf '%s' "$tok" ;;
    *) printf '' ;;
  esac
}

# tool を file 引数つきで呼ぶ base command。ローカル解決を優先 (node_modules/.bin) — npx の
# ネットワーク取得や版ずれを避ける。解決できなければ空 (= 呼び出し側はツリー全体に fallback)。
lint_scoped_base() {
  local script="$1" tool bin sub
  tool=$(lint_script_tool "$script")
  [ -n "$tool" ] || { printf ''; return 0; }

  if [ -x "node_modules/.bin/$tool" ]; then
    bin="node_modules/.bin/$tool"
  elif command -v "$tool" >/dev/null 2>&1; then
    bin="$tool"
  else
    printf ''; return 0
  fi

  case "$tool" in
    biome)
      # `biome check` は lint+format、`biome lint` は lint のみ。script の意図に合わせる。
      sub=check
      printf '%s' "$script" | grep -qE '(^|[[:space:]])lint([[:space:]]|$)' && sub=lint
      printf '%s %s' "$bin" "$sub"
      ;;
    prettier) printf '%s --check' "$bin" ;;
    *)        printf '%s' "$bin" ;;
  esac
}

# tool が扱う拡張子か。扱わない file を渡すと linter 自身がエラーを出して誤 block になる。
lint_ext_ok() {
  local tool="$1" file="$2" ext="${2##*.}"
  [ "$ext" = "$file" ] && ext=""   # 拡張子なし
  case "$tool" in
    prettier) return 0 ;;          # prettier はほぼ何でも扱う
    eslint|oxlint)
      case "$ext" in js|jsx|ts|tsx|mjs|cjs|mts|cts) return 0 ;; *) return 1 ;; esac ;;
    biome)
      case "$ext" in js|jsx|ts|tsx|mjs|cjs|mts|cts|json|jsonc|css) return 0 ;; *) return 1 ;; esac ;;
    ruff|flake8)
      case "$ext" in py|pyi) return 0 ;; *) return 1 ;; esac ;;
    rubocop)
      case "$ext" in rb|rake) return 0 ;; *) return 1 ;; esac ;;
    *) return 1 ;;
  esac
}
