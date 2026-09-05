#!/usr/bin/env bash
# branch-cleanup.sh — merge 済 branch の検証つき撤去 (local / remote)。
#
# なぜ script が要るか (= integrate skill の手順が構造的に完走できなかった):
#
#   integrate skill Step 5 は後片付けを `git branch -d feat/<id>-<topic>` と書いていた。
#   ところが GitHub の **squash merge** で PR を閉じる repo では、squash commit は元 branch の
#   commit を親に持たないので **branch は main の祖先にならない**。つまり `-d` は「未 merge」
#   と判定して必ず失敗する。残る手は `-D` だが、それは `block-dangerous-git-ops.sh` が
#   blocking する (= 未 merge branch の強制削除は作業を消すので正しい)。
#   結果、**手順が袋小路**になり後片付けだけが誰にも実行されないまま残った。実測 (2026-09-04、
#   dogfood 5 repo): local 1,000 本 / remote 2,000 本超が滞留し、うち 397 本が
#   「PR は MERGED なのに `-d` では消せない」状態だった。
#
# この script が塞ぐ穴:
#   `-D` を無条件に許すのではなく、**削除前に 1 本ずつ「安全である根拠」を取る**。
#   根拠は 2 種類だけ:
#     (a) branch が main ref の祖先である              → 内容は main にある      → `-d`
#     (b) その branch を head とする PR が MERGED である → 内容は squash で main にある → `-D`
#   (b) の判定は `gh` に問い合わせる。gh が無い / 未認証 / repo が GitHub でないときは
#   **(a) だけに縮退する** (= 判断材料が無い側では消さない。fail-safe)。
#
#   つまり `block-dangerous-git-ops.sh` の禁止は「**検証なしの** 強制削除」に対するもので、
#   本 script はその検証を供給する正規の経路。hook を無効化して手で `-D` を叩くのとは違う。
#
# 消さないもの (どの mode でも不変):
#   - main / master / trunk / develop / staging / production
#   - 現在 HEAD の branch、および linked worktree が checkout 中の branch
#   - PR が OPEN の branch
#   - 根拠 (a)(b) のどちらも取れない branch (= 未 push のローカル作業を含みうる)
#
# 使い方:
#   scripts/branch-cleanup.sh                 # dry-run (default)。何が消えるかだけ出す
#   scripts/branch-cleanup.sh --apply         # local branch を実際に消す
#   scripts/branch-cleanup.sh --remote        # remote 側も対象に含める (dry-run)
#   scripts/branch-cleanup.sh --remote --apply
#   scripts/branch-cleanup.sh --repo <dir>    # 対象 repo (default: cwd)
#   scripts/branch-cleanup.sh --backup <dir>  # 削除前に name+SHA を保存 (default: 保存する)
#
# 終了コード: 0 = 正常 (dry-run 含む) / 1 = 引数エラー / 2 = repo でない
#
# 恒久対策も忘れずに (この script は掃除であって蛇口は閉めない):
#   gh repo edit <owner>/<repo> --delete-branch-on-merge
#   → merge 時に head branch が自動削除される。これを入れないと remote は再び溜まる。
#     設定変更には ADMIN 権限が要る (WRITE では 404)。

set -u

APPLY=0
DO_REMOTE=0
REPO_DIR="."
BACKUP_DIR=""
NO_BACKUP=0

usage() {
  sed -n '/^# 使い方:/,/^#   scripts\/branch-cleanup.sh --backup/p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --apply)   APPLY=1; shift ;;
    --remote)  DO_REMOTE=1; shift ;;
    --repo)    REPO_DIR="${2:-}"; shift 2 ;;
    --backup)  BACKUP_DIR="${2:-}"; shift 2 ;;
    --no-backup) NO_BACKUP=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'branch-cleanup: unknown option: %s\n\n' "$1" >&2; usage >&2; exit 1 ;;
  esac
done

cd "$REPO_DIR" 2>/dev/null || { echo "branch-cleanup: no such dir: $REPO_DIR" >&2; exit 2; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "branch-cleanup: not a git repo: $REPO_DIR" >&2; exit 2; }

# ── main ref の解決 (repo-drift.sh と同じ優先順: origin/HEAD → origin/main → origin/master → local)
resolve_main_ref() {
  local r
  r=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null) && { echo "$r"; return 0; }
  for r in origin/main origin/master main master; do
    git rev-parse --verify --quiet "$r" >/dev/null 2>&1 && { echo "$r"; return 0; }
  done
  return 1
}

MAIN_REF="$(resolve_main_ref)" || { echo "branch-cleanup: main ref を解決できない" >&2; exit 2; }
MAIN_NAME="${MAIN_REF##*/}"

# ── 保護名 (削除対象から常に外す)
is_protected_name() {
  case "$1" in
    main|master|trunk|develop|staging|production|HEAD) return 0 ;;
    "$MAIN_NAME") return 0 ;;
  esac
  return 1
}

# ── worktree が checkout 中の branch (自分の HEAD を含む)
CHECKED_OUT="$(git worktree list --porcelain 2>/dev/null | sed -n 's|^branch refs/heads/||p')"
is_checked_out() { printf '%s\n' "$CHECKED_OUT" | grep -qxF "$1"; }

# ── PR 状態テーブル。gh が使えないときは空 = (b) 判定を諦めて (a) だけに縮退する。
PR_MERGED=""
PR_OPEN=""
GH_OK=0
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  # 成否は gh の終了コードで見る。「PR が 0 件の repo」と「gh が使えない」を出力の空で
  # 混同すると、前者で縮退モードの警告を出してしまう (実測: PR を使っていない個人 repo)。
  if _prs="$(gh pr list --state all --limit 2000 --json headRefName,state \
              --jq '.[]|.headRefName+"|"+.state' 2>/dev/null)"; then
    PR_MERGED="$(printf '%s\n' "$_prs" | sed -n 's/|MERGED$//p' | sort -u)"
    PR_OPEN="$(printf '%s\n' "$_prs" | sed -n 's/|OPEN$//p' | sort -u)"
    GH_OK=1
  fi
fi
is_pr_merged() { [ "$GH_OK" = 1 ] && printf '%s\n' "$PR_MERGED" | grep -qxF "$1"; }
is_pr_open()   { [ "$GH_OK" = 1 ] && printf '%s\n' "$PR_OPEN"   | grep -qxF "$1"; }

is_ancestor() { git merge-base --is-ancestor "refs/heads/$1" "$MAIN_REF" 2>/dev/null; }

# ── backup (削除前に name+SHA を残す。復元は git branch <name> <sha>)
# repo の中には置かない (untracked file を増やして git status を汚すため)。
if [ -z "$BACKUP_DIR" ] && [ "$NO_BACKUP" = 0 ]; then
  _top="$(git rev-parse --show-toplevel)"
  BACKUP_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/project-bootstrap/branch-backup/${_top##*/}"
fi
BACKUP_FILE=""
if [ "$NO_BACKUP" = 0 ] && [ "$APPLY" = 1 ]; then
  mkdir -p "$BACKUP_DIR" 2>/dev/null || true
  BACKUP_FILE="$BACKUP_DIR/$(date +%Y%m%d-%H%M%S).refs"
  {
    echo "# branch-cleanup backup — $(date -Iseconds 2>/dev/null || date)"
    echo "# restore local : git branch <name> <sha>"
    echo "# restore remote: git push origin <sha>:refs/heads/<name>"
    git for-each-ref --format='%(objectname) %(refname)' refs/heads refs/remotes
  } > "$BACKUP_FILE" 2>/dev/null || BACKUP_FILE=""
fi

echo "repo      : $(git rev-parse --show-toplevel)"
echo "main ref  : $MAIN_REF"
if [ "$GH_OK" = 1 ]; then
  echo "PR 情報   : gh から取得 (merged $(printf '%s\n' "$PR_MERGED" | grep -c . ) 件 / open $(printf '%s\n' "$PR_OPEN" | grep -c .) 件)"
else
  echo "PR 情報   : 取得できず — squash merge 済 branch は判定できないので残す (縮退モード)"
fi
[ -n "$BACKUP_FILE" ] && echo "backup    : $BACKUP_FILE"
[ "$APPLY" = 1 ] || echo "mode      : DRY-RUN (--apply で実行)"
echo

# ── local branch
n_anc=0; n_sq=0; n_keep=0; n_fail=0
while IFS= read -r br; do
  [ -n "$br" ] || continue
  is_protected_name "$br" && continue
  if is_checked_out "$br"; then continue; fi
  if is_pr_open "$br"; then continue; fi

  if is_ancestor "$br"; then
    if [ "$APPLY" = 1 ]; then
      # `git branch -d` は **HEAD (と upstream)** を基準に merge 済かを見る。こちらの根拠は
      # MAIN_REF (= origin/main) なので、**ローカル main が origin/main より遅れていると
      # -d は「未 merge」と言って失敗する** (実測 2026-09-05: appo-followup / rust-100-knocks)。
      # 根拠 (a) は既に取れているので、その場合だけ -D に落として消す。ここで -D を使うのは
      # 「検証を省く」ことではなく、-d が見ている基準がこちらの基準と違うだけ。
      if git branch -d "$br" >/dev/null 2>&1 || git branch -D "$br" >/dev/null 2>&1; then
        n_anc=$((n_anc+1))
      else
        n_fail=$((n_fail+1)); echo "  ! 失敗 (local, merged) $br"
      fi
    else
      n_anc=$((n_anc+1)); echo "  - [merged]  $br"
    fi
  elif is_pr_merged "$br"; then
    if [ "$APPLY" = 1 ]; then
      # 根拠 (b): PR が MERGED。内容は squash commit として main にある。
      if git branch -D "$br" >/dev/null 2>&1; then n_sq=$((n_sq+1)); else n_fail=$((n_fail+1)); echo "  ! 失敗 (local, squashed) $br"; fi
    else
      n_sq=$((n_sq+1)); echo "  - [squashed] $br"
    fi
  else
    n_keep=$((n_keep+1))
  fi
done <<EOF
$(git for-each-ref --format='%(refname:short)' refs/heads)
EOF

echo "local : merged $n_anc 本 / squash-merged $n_sq 本 を削除$([ "$APPLY" = 1 ] || echo '予定')、$n_keep 本は根拠が無いので残す$([ "$n_fail" -gt 0 ] && echo " (失敗 $n_fail)")"

# ── remote branch (--remote のときだけ)
if [ "$DO_REMOTE" = 1 ]; then
  if [ "$GH_OK" != 1 ]; then
    echo "remote: PR 情報が取れないので remote 側はスキップした (判断材料なしでは消さない)"
  else
    rm_list=""
    n_rm=0
    while IFS= read -r rb; do
      br="${rb#origin/}"
      [ -n "$br" ] || continue
      is_protected_name "$br" && continue
      is_pr_open "$br" && continue
      if is_pr_merged "$br"; then rm_list="$rm_list $br"; n_rm=$((n_rm+1)); fi
    done <<EOF
$(git for-each-ref --format='%(refname:short)' refs/remotes/origin)
EOF
    if [ "$n_rm" = 0 ]; then
      echo "remote: 削除対象なし"
    elif [ "$APPLY" != 1 ]; then
      echo "remote: $n_rm 本が削除対象 (--apply で実行)"
    else
      # 1 本でも存在しない ref が混ざると push 全体が失敗するので、
      # chunk 失敗時は 1 本ずつ retry する (= 部分的な取りこぼしを作らない)。
      ok=0; ng=0
      # shellcheck disable=SC2086
      set -- $rm_list
      while [ $# -gt 0 ]; do
        chunk=""; i=0
        while [ $# -gt 0 ] && [ "$i" -lt 30 ]; do chunk="$chunk $1"; shift; i=$((i+1)); done
        # shellcheck disable=SC2086
        if git push origin --delete $chunk >/dev/null 2>&1; then
          ok=$((ok+i))
        else
          for b in $chunk; do
            if git push origin --delete "$b" >/dev/null 2>&1; then ok=$((ok+1)); else ng=$((ng+1)); echo "  ! 失敗 (remote) $b"; fi
          done
        fi
      done
      echo "remote: $ok 本削除$([ "$ng" -gt 0 ] && echo " / $ng 本失敗")"
    fi
  fi
fi

echo
if [ "$APPLY" != 1 ]; then
  echo "→ 実行するには --apply を付ける。"
fi
echo "→ 蛇口を閉めるには: gh repo edit <owner>/<repo> --delete-branch-on-merge (ADMIN 権限が要る)"
