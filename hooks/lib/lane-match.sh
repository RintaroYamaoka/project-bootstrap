#!/usr/bin/env bash
# Shared lane-matching engine.
#
# `.bootstrap/lane` (旧 `.bootstrap-lane`) は worktree root に置かれた「触ってよい file」の
# glob 宣言 (1 行 1 glob)。この判定を **単一権威** に集約する — 編集時 (block-out-of-lane-edit)
# と commit 時 (block-out-of-lane-commit) が別々に glob を解釈すると、片方だけが緩い穴になる
# (= detect-test-suite.sh を test/merge 両関所で共有しているのと同じ思想、ADR 0005 guard 1)。
#
# lane_allows <rel-path> <lane-file>
#   return 0 = lane 内 (許可) / 1 = lane 外
#
# lane_owning_worktree <abs-path> <top>
#   abs-path が **同一 repo の別 worktree** の中に在るなら、その root を stdout に出して return 0。
#   どの worktree にも属さない (= repo 外。/tmp scratchpad 等) なら return 1。
#   これは「lane 外だと確定できる」ケースを fail-open に逃さないために要る (下記)。

# lane glob の照合。bash [[ $rel == $pat ]] の glob では `*` が `/` も跨ぐので
# `*` `**` 両方が nested に効く。空行 / # コメントは無視。
# Include guard — dispatcher が 1 プロセスに複数 gate を source するときの再読込抑止。
[ -n "${_BOOTSTRAP_LIB_LANE_MATCH:-}" ] && return 0
_BOOTSTRAP_LIB_LANE_MATCH=1

lane_allows() {
  local rel="$1" lane="$2" pat
  [ -f "$lane" ] || return 1
  while IFS= read -r pat || [ -n "$pat" ]; do
    pat="${pat#"${pat%%[![:space:]]*}"}"   # ltrim
    pat="${pat%"${pat##*[![:space:]]}"}"    # rtrim
    [ -z "$pat" ] && continue
    case "$pat" in \#*) continue ;; esac
    # shellcheck disable=SC2053
    if [[ "$rel" == $pat ]]; then
      return 0
    fi
  done < "$lane"
  return 1
}

# 絶対 path が同一 repo の *別* worktree に属するか。
#
# なぜ要るか: lane worker が `/main-repo/scripts/x.mjs` のような **worktree 外の絶対 path** を
# 編集する行為は、かつて「判断不能」として fail-open していた。だがこれは判断不能ではない —
# その path が同一 repo の別 worktree の中に在るなら、**定義上 lane の外**だと確定できる。
# 根拠不在 (= repo 外で判断材料が無い) なら fail-open、解析できて違反と分かるなら fail-closed。
lane_owning_worktree() {
  local file="$1" top="$2" root
  command -v git >/dev/null 2>&1 || return 1
  while IFS= read -r root; do
    [ -n "$root" ] || continue
    root="${root%/}"
    [ "$root" = "$top" ] && continue
    case "$file" in
      "$root"/*) printf '%s' "$root"; return 0 ;;
    esac
  done < <(git worktree list --porcelain 2>/dev/null \
             | sed -n 's/^worktree //p' | tr '\\' '/' | tr -s '/')
  return 1
}
