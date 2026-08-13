#!/usr/bin/env bash
#
# 既存ユーザーへの設定の行き渡らせ
#
# /etc/skel が効くのは「これから作られるユーザー」だけなので、
# install.sh を実行した本人を含む既存ユーザーには何も届かない。
# 実際、xremap の systemd ユニットは ConditionPathExists で
# ~/.config/xremap/config.yml を要求するため、これがないと起動すらしない。
#
# このモジュールは既存ユーザーに対して次を行う:
#   1. /etc/skel のうち「まだ存在しないファイル」だけを配る (既存の設定は壊さない)
#   2. xremap が入力デバイスを読めるよう input グループに追加する
#
# ログインシェルの変更だけは行わず、chsh の案内にとどめる
# (利用者が意図せずシェルを変えられるのを避けるため)。
#
set -euo pipefail

MODULE_NAME="70-existing-users"
# shellcheck source=lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

SKEL=/etc/skel

# 対象は通常のログインユーザー (UID 1000-59999) でホームがあるもの
list_regular_users() {
  local user uid home shell
  while IFS=: read -r user _ uid _ _ home shell; do
    case "$shell" in
      */nologin | */false) continue ;;
    esac
    if [ "$uid" -ge 1000 ] && [ "$uid" -lt 60000 ] && [ -d "$home" ]; then
      printf '%s\t%s\t%s\n' "$user" "$home" "$shell"
    fi
  done </etc/passwd
}

# /etc/skel の内容のうち、まだ存在しないものだけをコピーする。
# 対象ユーザー自身として実行することで所有者が自動的に正しくなる。
seed_skel_into_home() {
  local user="$1" home="$2" before after

  before="$(sudo_count_files "$home")"

  # --update=none は「既にあるものは上書きしない」。
  # GNU coreutils 9.3 以降で使える (-n は非推奨の警告が出る)。
  if ! runuser -u "$user" -- \
    cp -r --update=none --preserve=mode,timestamps "${SKEL}/." "${home}/"; then
    warn "${user} のホームへの配布に失敗しました。"
    return 0
  fi

  after="$(sudo_count_files "$home")"
  if [ "$before" -eq "$after" ]; then
    log "変更なし: ${home} (配布済み)"
  else
    log "配布: ${home} に $((after - before)) 個のファイルを追加しました"
  fi
}

sudo_count_files() {
  find "$1" -type f 2>/dev/null | wc -l
}

add_to_input_group() {
  local user="$1"
  if id -nG "$user" | tr ' ' '\n' | grep -qx input; then
    log "変更なし: ${user} は既に input グループに入っています"
    return 0
  fi
  usermod -aG input "$user"
  log "追加: ${user} を input グループに入れました (反映には再ログインが必要)"
}

main() {
  require_root

  [ -d "$SKEL" ] || die "/etc/skel がありません。先に他のモジュールを実行してください。"

  local user home shell count=0
  while IFS=$'\t' read -r user home shell; do
    log "対象ユーザー: ${user} (${home})"
    seed_skel_into_home "$user" "$home"
    add_to_input_group "$user"

    case "$shell" in
      /bin/zsh | /usr/bin/zsh) ;;
      *)
        log "  ${user} のログインシェルは ${shell} です。zsh にするには: chsh -s /bin/zsh ${user}"
        ;;
    esac
    count=$((count + 1))
  done < <(list_regular_users)

  if [ "$count" -eq 0 ]; then
    log "対象となる既存ユーザーはいませんでした。"
  else
    log "既存ユーザー ${count} 人に設定を配布しました。"
    log "既に同名のファイルがある場合は上書きしていません。"
  fi
}

main "$@"
