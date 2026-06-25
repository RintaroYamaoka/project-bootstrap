# verification plan — feat/P0-protected-branch-tokenizer
#
# 意図: 保護ブランチ push gate の 2 つの実バイパス (複合コマンドの last-only / path-prefixed git)
# を塞ぎ、benign な push を新たに false-block しない「厳密改善」であること。
# 継ぎ目: gate は shell コマンド文字列のトークン化 = 「行為の文字列 proxy」という継ぎ目そのもの。
# リスクは新しい穴 (proxy の抜け) か既存挙動の回帰。オラクルは AI の判断でなく **実 hook の exit
# code を sandbox repo (.bootstrap-protected あり) で観測した値** + 全 suite の green に置く。
# kill-question (各 PASS): 「このテストが緑のままユーザーが困るか?」— false-block 行 (過剰遮断) と
# regression 行 (過小遮断) の両方向で塞いでいる。
#
# STATUS | kind | behaviour | oracle | by | evidence/note

PASS  | bypass-closed | 複合 `git push origin main && git push origin feat/x` が保護 main を捕捉して block (last-only 回帰の解消) | 実 hook exit 2 (sandbox + .bootstrap-protected) | ai | end-to-end 14-case / unit: push_destination_branches compound-&& 両方 emit
PASS  | bypass-closed | path-prefixed `/usr/bin/git push origin main` と `./git push` が block | 実 hook exit 2 | ai | end-to-end / unit: cmd_has_git_push '/'許容・mygit/legit 非該当
PASS  | regression    | 従来 block していた入力が全て維持 (bare / `HEAD:main` / `+main` / `refs/heads/main` / 保護 main 上の暗黙 push) | 実 hook exit 2 | ai | end-to-end strict-improvement set (旧挙動と byte 互換の message/exit)
PASS  | false-block   | benign が新たに block されない (`feat/x` / 両方非保護の複合 / `--repo` 値 / `git status` / `mygit push` / `&&` 後の echo) | 実 hook exit 0 | ai | end-to-end + unit: remote 非 emit・value-flag 値スキップ・separator で再武装しない
PASS  | drift-guard   | 新 lib が lib/merge-targets.sh と同型の単一権威で、別系統の照合を増やしていない | code review + 全 suite | ai | review verdict approve / 30 suites 0 failed / unit 31 assertions green
DROP  | scope         | 引用符内に現れる separator (`-o "a && b"`) の完全な shell parse | n/a | ai | merge-targets.sh パターンから継承した既知 fail-open、lib ヘッダに明記。commit-time arch/test gate + CI が net (確立済みパターンと同じ)
