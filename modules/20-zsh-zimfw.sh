#!/usr/bin/env bash
#
# F2. zsh + zimfw
#
# - 新規ユーザーの既定シェルを zsh にする (/etc/adduser.conf)
# - zimfw 本体をシステム共有パスに置く
# - /etc/skel に .zshrc / .zimrc と、取得済みの zimfw モジュール一式を置く
#
# init.zsh (zimfw が生成する読み込みスクリプト) は skel に置かない。
# 生成物に絶対パスが含まれ得るため、各ユーザーの初回シェル起動時に
# .zshrc のブートストラップが生成する。モジュール本体は skel に入っているので
# 初回起動時にネットワークは不要。
#
set -euo pipefail

MODULE_NAME="20-zsh-zimfw"
# shellcheck source=lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

ZIMFW_VERSION="v1.20.0"
ZIMFW_URL="https://github.com/zimfw/zimfw/releases/download/${ZIMFW_VERSION}/zimfw.zsh"
ZIMFW_SHA256="f9362a5c5a1cfd9b54e45b9dbb651986908f838bc68cb487dec33a0c79069f84"
ZIMFW_SHARE_DIR="/usr/local/share/zimfw"
ZIMFW_SCRIPT="${ZIMFW_SHARE_DIR}/zimfw.zsh"

SKEL=/etc/skel
SKEL_ZIM_HOME="${SKEL}/.zim"

install_zimfw_script() {
  install -d "$ZIMFW_SHARE_DIR"
  download_verify "$ZIMFW_URL" "$ZIMFW_SHA256" "$ZIMFW_SCRIPT"
  chmod 0644 "$ZIMFW_SCRIPT"
}

install_skel_dotfiles() {
  # .zshenv は /etc/zsh/zshrc より先に読まれる必要がある
  # (システム側の compinit を止めて zimfw に任せるため)
  install_file "${REPO_ROOT}/files/skel/.zshenv" "${SKEL}/.zshenv" 0644
  install_file "${REPO_ROOT}/files/skel/.zshrc" "${SKEL}/.zshrc" 0644
  install_file "${REPO_ROOT}/files/skel/.zimrc" "${SKEL}/.zimrc" 0644
}

# /etc/skel/.zim/modules に zimfw モジュールの実体 (git clone) を用意する。
# ここで取得しておくことで、各ユーザーの初回シェル起動はオフラインで完結する。
seed_skel_modules() {
  install -d "$SKEL_ZIM_HOME"

  log "zimfw モジュールを ${SKEL_ZIM_HOME}/modules に取得します"
  # HOME / ZDOTDIR / ZIM_HOME を skel に向けて zimfw を実行する。
  # install サブコマンドは未取得のモジュールだけを clone するので冪等。
  env -i \
    PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    HOME="$SKEL" \
    ZDOTDIR="$SKEL" \
    ZIM_HOME="$SKEL_ZIM_HOME" \
    TERM=dumb \
    zsh -f -c "source '${ZIMFW_SCRIPT}' install" ||
    die "zimfw のモジュール取得に失敗しました。"

  # init.zsh と .zwc は skel に残さない。各ユーザーの初回起動時に生成させる。
  find "$SKEL_ZIM_HOME" -maxdepth 1 -name 'init.zsh*' -delete
  find "$SKEL_ZIM_HOME" -name '*.zwc' -delete

  # skel 配下は誰でも読める必要がある
  chmod -R a+rX "$SKEL_ZIM_HOME"

  local count
  count="$(find "${SKEL_ZIM_HOME}/modules" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)"
  log "skel に配置された zimfw モジュール数: ${count}"
}

set_default_shell_for_new_users() {
  set_conf_key /etc/adduser.conf DSHELL /bin/zsh

  # 既存ユーザーのシェルは自動変更しない (要件どおり案内のみ)
  local u
  while IFS=: read -r u _ uid _ _ _ shell; do
    if [ "$uid" -ge 1000 ] && [ "$uid" -lt 60000 ] && [ "$shell" != "/bin/zsh" ] &&
      [ "$shell" != "/usr/bin/zsh" ]; then
      log "既存ユーザー ${u} のシェルは ${shell} です。切り替えるには: chsh -s /bin/zsh ${u}"
    fi
  done </etc/passwd
}

main() {
  require_root

  command -v zsh >/dev/null 2>&1 || die "zsh が見つかりません。先に 10-packages.sh を実行してください。"

  install_zimfw_script
  install_skel_dotfiles
  seed_skel_modules
  set_default_shell_for_new_users

  log "zimfw ${ZIMFW_VERSION} を ${ZIMFW_SCRIPT} に配置しました。"
}

main "$@"
