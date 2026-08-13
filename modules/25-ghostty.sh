#!/usr/bin/env bash
#
# F2.5. Ghostty
#
# - /etc/skel に Ghostty の設定 (Alt+C / Alt+V のネイティブ keybind) を置く
# - システム既定ターミナルを Ghostty にする
# - Ctrl+Alt+T で Ghostty が起動するよう dconf のシステム既定値を設定する
#
# Ubuntu 26.04 (GNOME 50) では、既定ターミナルは xdg-terminal-exec が
# xdg-terminals.list 系のファイルを読んで決める。
# また gnome-settings-daemon 50 の media-keys スキーマから terminal キーが
# なくなっているため、Ctrl+Alt+T はカスタムキーバインドとして登録する。
# 詳しくは README の「設計判断」節を参照。
#
# Ptyxis はアンインストールしない (公式構成からの逸脱を最小化するため)。
#
set -euo pipefail

MODULE_NAME="25-ghostty"
# shellcheck source=lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

GHOSTTY_DESKTOP_ID="com.mitchellh.ghostty.desktop"
DCONF_GHOSTTY_FILE="${DCONF_DB_DIR}/20-ghostty"
CUSTOM_KEYBINDING_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"

install_skel_config() {
  install_file "${REPO_ROOT}/files/skel/.config/ghostty/config" \
    /etc/skel/.config/ghostty/config 0644
}

# xdg-terminal-exec は XDG_CURRENT_DESKTOP に含まれるデスクトップ名ごとに
# <desktop>-xdg-terminals.list を探し、最後に xdg-terminals.list を見る。
# Ubuntu の XDG_CURRENT_DESKTOP は "ubuntu:GNOME" なので 3 種類とも置く。
# システム既定は XDG_CONFIG_DIRS 上、すなわち /etc/xdg に置く。
# ユーザーは ~/.config/ 側に同名ファイルを置けば上書きできる。
set_default_terminal() {
  local f
  for f in ubuntu-xdg-terminals.list gnome-xdg-terminals.list xdg-terminals.list; do
    write_file "/etc/xdg/${f}" 0644 <<EOF
${GHOSTTY_DESKTOP_ID}
EOF
  done

  # Debian 系のツール (gio open など) が見る x-terminal-emulator も合わせる
  if update-alternatives --list x-terminal-emulator 2>/dev/null | grep -qx /usr/bin/ghostty; then
    update-alternatives --set x-terminal-emulator /usr/bin/ghostty >/dev/null
    log "update-alternatives: x-terminal-emulator -> /usr/bin/ghostty"
  else
    log "x-terminal-emulator の候補に ghostty がないためスキップします"
  fi
}

# Ctrl+Alt+T をカスタムキーバインドとして登録する。
# コマンドは ghostty を直接呼ばず xdg-terminal-exec 経由にして、
# 既定ターミナルの定義箇所を xdg-terminals.list 1 か所に集約する。
set_terminal_shortcut() {
  ensure_dconf_profile
  write_file "$DCONF_GHOSTTY_FILE" 0644 <<EOF
# Ctrl+Alt+T で既定ターミナル (= Ghostty) を開く。
# GNOME 50 の gnome-settings-daemon には組み込みの terminal キーがないため、
# カスタムキーバインドとして登録する。
[org/gnome/settings-daemon/plugins/media-keys]
custom-keybindings=['${CUSTOM_KEYBINDING_PATH}']

[org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0]
name='Open Terminal'
command='xdg-terminal-exec'
binding='<Primary><Alt>t'
EOF
  dconf_update
}

main() {
  require_root

  command -v ghostty >/dev/null 2>&1 ||
    die "ghostty が見つかりません。先に 10-packages.sh を実行してください。"
  [ -f "/usr/share/applications/${GHOSTTY_DESKTOP_ID}" ] ||
    warn "/usr/share/applications/${GHOSTTY_DESKTOP_ID} が見つかりません。"

  install_skel_config
  set_default_terminal
  set_terminal_shortcut

  log "既定ターミナル: ${GHOSTTY_DESKTOP_ID} (/etc/xdg/*xdg-terminals.list)"
}

main "$@"
