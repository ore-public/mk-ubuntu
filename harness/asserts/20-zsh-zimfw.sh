#!/usr/bin/env bash
# F2. zsh + zimfw の検証。
set -uo pipefail
# shellcheck source=harness/asserts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

check_contains /etc/adduser.conf "^DSHELL=/bin/zsh$" \
  "/etc/adduser.conf の DSHELL が /bin/zsh"
check "DSHELL の行が 1 行だけ (追記の重複がない)" \
  bash -c "[ \"\$(grep -c '^DSHELL=' /etc/adduser.conf)\" -eq 1 ]"

check_file /usr/local/share/zimfw/zimfw.zsh
check_file /etc/skel/.zshenv
check_file /etc/skel/.zshrc
check_file /etc/skel/.zimrc
check_file /etc/skel/.zshrc.local
check_file /etc/skel/.zimrc.local

# システム側の compinit を止めて zimfw の completion モジュールに任せる
check_contains /etc/skel/.zshenv "^skip_global_compinit=1$" \
  "/etc/skel/.zshenv が skip_global_compinit=1 を設定している"

check_contains /etc/skel/.zimrc "^zmodule fzf$" \
  "/etc/skel/.zimrc に zmodule fzf がある"
check_contains /etc/skel/.zshrc "^alias bat=\"batcat\"$" \
  "/etc/skel/.zshrc に alias bat=\"batcat\" がある"
check_contains /etc/skel/.zshrc "zimfw.zsh" \
  "/etc/skel/.zshrc が zimfw を読み込む"

# モジュールの実体が skel に取得済みであること (初回ログインをオフラインで完結させる)
check_dir /etc/skel/.zim/modules
for m in environment git input termtitle utility fzf completion asciiship \
  zsh-completions zsh-syntax-highlighting zsh-history-substring-search zsh-autosuggestions; do
  check_dir "/etc/skel/.zim/modules/${m}" "zimfw モジュールが skel にある: ${m}"
done

# init.zsh は各ユーザーが初回起動時に生成する (skel には置かない)
check "/etc/skel/.zim/init.zsh が存在しない" test ! -e /etc/skel/.zim/init.zsh

check "skel 配下が全ユーザーから読める" \
  bash -c "[ -r /etc/skel/.zim/modules/fzf ]"

assert_exit
