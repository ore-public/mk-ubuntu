#!/usr/bin/env bash
# F2.5. Ghostty と既定ターミナルの検証。
set -uo pipefail
# shellcheck source=harness/asserts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

check_file /etc/skel/.config/ghostty/config
check_contains /etc/skel/.config/ghostty/config "^keybind = alt\+c=copy_to_clipboard$" \
  "Ghostty の設定に alt+c=copy_to_clipboard がある"
check_contains /etc/skel/.config/ghostty/config "^keybind = alt\+v=paste_from_clipboard$" \
  "Ghostty の設定に alt+v=paste_from_clipboard がある"

check_file /etc/skel/.config/ghostty/config.local
check_contains /etc/skel/.config/ghostty/config "^config-file = \?config\.local$" \
  "Ghostty の設定が個人用 config.local を任意読み込みする"

check_file /usr/share/applications/com.mitchellh.ghostty.desktop

# 既定ターミナル: xdg-terminal-exec が読む 3 種類のリスト
for f in ubuntu-xdg-terminals.list gnome-xdg-terminals.list xdg-terminals.list; do
  check_contains "/etc/xdg/${f}" "^com\.mitchellh\.ghostty\.desktop$" \
    "/etc/xdg/${f} が Ghostty を指している"
done

check "xdg-terminal-exec が導入済み" bash -c "command -v xdg-terminal-exec"

# Ctrl+Alt+T のカスタムキーバインド (dconf システム既定値)
check_cmd_output "dconf に Ctrl+Alt+T のカスタムキーバインドがある" "<Primary><Alt>t" \
  gsettings get \
  org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ \
  binding
check_cmd_output "そのキーバインドのコマンドが xdg-terminal-exec である" "xdg-terminal-exec" \
  gsettings get \
  org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ \
  command
check_cmd_output "custom-keybindings にそのパスが登録されている" "custom0" \
  gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings

assert_exit
