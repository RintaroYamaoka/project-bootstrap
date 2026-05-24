#!/usr/bin/env bash
# Dependency-direction engine for project-bootstrap.
#
# GENERIC — ships no rules. A project declares its architecture in a `.bootstrap-arch`
# manifest (repo root, committed). This engine answers: which layer a file belongs to,
# what repo path an import specifier resolves to, what a file imports, and whether a
# file's imports violate the declared direction. Cross-layer is default-deny; same-layer
# and external (undeclared) targets are always allowed.
#
# jq-free, pure bash (jq is absent on many machines; this matches the other hooks).
# Sourced by block-arch-violations.sh (commit-time) and block-cross-layer-import.sh (edit-time).
#
# Manifest grammar (one directive per line, `#` starts a comment):
#   layer NAME = GLOB[, GLOB...]      # a file's layer = the layer whose longest glob matches
#   alias PREFIX => PATH              # import specifier prefix -> repo-relative path
#   allow FROM -> TO[, TO...]         # FROM may import TO; any other cross-layer edge is denied
#
# Supported languages for import extraction: ts/tsx/js/jsx/mjs/cjs, py.
# Other extensions extract nothing (file is not checked) until their extractor lands.

declare -gA ARCH_LAYER_GLOBS=()   # layer name -> newline-separated globs
declare -gA ARCH_ALIAS=()         # alias prefix -> replacement path (repo-relative)
declare -gA ARCH_ALLOW=()         # "FROM>TO" -> 1
ARCH_LAYER_NAMES=""               # space-separated layer names

_arch_trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }

# split $1 on commas into trimmed non-empty items, one per line (no glob expansion).
_arch_split_csv() {
  printf '%s' "$1" | tr ',' '\n' | while IFS= read -r x || [ -n "$x" ]; do
    x="$(_arch_trim "$x")"; [ -n "$x" ] && printf '%s\n' "$x"
  done
}

# normalize a path: drop "." segments, resolve ".." segments, no leading "./".
_arch_norm() {
  local p="$1" part out=()
  while IFS= read -r part || [ -n "$part" ]; do
    case "$part" in
      ''|.) ;;
      ..) [ ${#out[@]} -gt 0 ] && unset 'out[$((${#out[@]}-1))]' ;;
      *) out+=("$part") ;;
    esac
  done < <(printf '%s' "$p" | tr '/' '\n')
  local IFS='/'; printf '%s' "${out[*]}"
}

arch_load_manifest() {
  local f="$1" line rest
  ARCH_LAYER_GLOBS=(); ARCH_ALIAS=(); ARCH_ALLOW=(); ARCH_LAYER_NAMES=""
  [ -f "$f" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="$(_arch_trim "$line")"
    [ -z "$line" ] && continue
    case "$line" in
      layer\ *)
        rest="${line#layer }"
        local name globs g normalized=""
        name="$(_arch_trim "${rest%%=*}")"
        globs="${rest#*=}"
        while IFS= read -r g; do normalized="${normalized}${g}"$'\n'; done < <(_arch_split_csv "$globs")
        ARCH_LAYER_GLOBS["$name"]="$normalized"
        ARCH_LAYER_NAMES="$ARCH_LAYER_NAMES $name"
        ;;
      alias\ *)
        rest="${line#alias }"
        local pfx path
        pfx="$(_arch_trim "${rest%%=>*}")"
        path="$(_arch_trim "${rest#*=>}")"
        path="${path#./}"; path="${path%/}"
        ARCH_ALIAS["$pfx"]="$path"
        ;;
      allow\ *)
        rest="${line#allow }"
        local from t
        from="$(_arch_trim "${rest%%->*}")"
        while IFS= read -r t; do ARCH_ALLOW["$from>$t"]=1; done < <(_arch_split_csv "${rest#*->}")
        ;;
    esac
  done < "$f"
  ARCH_LAYER_NAMES="$(_arch_trim "$ARCH_LAYER_NAMES")"
}

_arch_glob_match() { local p="$1" g="$2"; [[ "$p" == $g ]]; }

# arch_layer_of <repo-rel-path> -> layer name with the longest matching glob, or "".
arch_layer_of() {
  local path="$1" name g best="" bestlen=-1
  for name in $ARCH_LAYER_NAMES; do
    while IFS= read -r g; do
      [ -z "$g" ] && continue
      if _arch_glob_match "$path" "$g" && [ "${#g}" -gt "$bestlen" ]; then
        bestlen=${#g}; best="$name"
      fi
    done <<< "${ARCH_LAYER_GLOBS[$name]}"
  done
  printf '%s' "$best"
}

# arch_resolve <specifier> <from-repo-rel-file> -> repo-rel target path, or "" if external.
arch_resolve() {
  local spec="$1" from="$2" pfx rest base dir cand
  for pfx in "${!ARCH_ALIAS[@]}"; do
    case "$spec" in
      "$pfx"*)
        rest="${spec#"$pfx"}"
        base="${ARCH_ALIAS[$pfx]}"
        _arch_norm "${base:+$base/}$rest"
        return 0 ;;
    esac
  done
  case "$spec" in
    ./*|../*)
      dir="$(dirname "$from")"
      _arch_norm "$dir/$spec"
      return 0 ;;
  esac
  # dotted module (python `a.b.c`): map to a/b/c only if it lands in a declared layer.
  case "$spec" in
    *.*)
      cand="${spec//.//}"
      if [ -n "$(arch_layer_of "$cand")" ]; then _arch_norm "$cand"; return 0; fi
      ;;
  esac
  printf ''   # external / unresolvable
}

# import-specifier extractors (read source on stdin, emit one specifier per line, source order).
_arch_extract_jsts() {
  local src; src="$(cat)"
  printf '%s' "$src" \
    | grep -oE "(from[[:space:]]+|import[[:space:]]+|require[[:space:]]*\([[:space:]]*|import[[:space:]]*\([[:space:]]*)['\"][^'\"]+['\"]" \
    | sed -E "s/.*['\"]([^'\"]+)['\"].*/\1/"
}
_arch_extract_py() {
  cat | grep -oE "^[[:space:]]*(from|import)[[:space:]]+[A-Za-z0-9_.]+" \
      | sed -E 's/^[[:space:]]*(from|import)[[:space:]]+//'
}
arch_extract() {
  case "$1" in
    ts|tsx|js|jsx|mjs|cjs) _arch_extract_jsts ;;
    py) _arch_extract_py ;;
    *) cat >/dev/null ;;
  esac
}

# arch_check_imports <repo-rel-file> <ext>  (reads source on stdin)
# Emits one line per forbidden import; returns 1 if any violation, else 0.
arch_check_imports() {
  local file="$1" ext="$2" src spec tgt tlayer slayer rc=0
  slayer="$(arch_layer_of "$file")"
  if [ -z "$slayer" ]; then cat >/dev/null; return 0; fi
  src="$(cat)"
  while IFS= read -r spec; do
    [ -z "$spec" ] && continue
    tgt="$(arch_resolve "$spec" "$file")"
    [ -z "$tgt" ] && continue
    tlayer="$(arch_layer_of "$tgt")"
    [ -z "$tlayer" ] && continue
    [ "$tlayer" = "$slayer" ] && continue
    if [ -z "${ARCH_ALLOW["$slayer>$tlayer"]:-}" ]; then
      printf '%s (%s) imports %s (%s) — disallowed edge %s -> %s\n' "$file" "$slayer" "$spec" "$tlayer" "$slayer" "$tlayer"
      rc=1
    fi
  done < <(printf '%s' "$src" | arch_extract "$ext")
  return $rc
}
