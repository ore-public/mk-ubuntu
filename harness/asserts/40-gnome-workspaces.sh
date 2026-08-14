#!/usr/bin/env bash
# F4. ワークスペース設定 (dconf システム既定値) の検証。
set -uo pipefail
# shellcheck source=harness/asserts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

check_file /etc/dconf/profile/user
check_contains /etc/dconf/profile/user "^system-db:local$" \
  "dconf プロファイルが system-db:local を含む"
check "dconf のバイナリ DB が生成されている" test -f /etc/dconf/db/local

check_cmd_output "dynamic-workspaces が false" "^false$" \
  gsettings get org.gnome.mutter dynamic-workspaces
check_cmd_output "num-workspaces が 10" "^10$" \
  gsettings get org.gnome.desktop.wm.preferences num-workspaces

# Ctrl+1 〜 Ctrl+0 / Ctrl+Shift+1 〜 Ctrl+Shift+0
for i in 1 2 3 4 5 6 7 8 9; do
  check_cmd_output "switch-to-workspace-${i} が <Primary>${i}" "<Primary>${i}" \
    gsettings get org.gnome.desktop.wm.keybindings "switch-to-workspace-${i}"
  check_cmd_output "move-to-workspace-${i} が <Primary><Shift>${i}" "<Primary><Shift>${i}" \
    gsettings get org.gnome.desktop.wm.keybindings "move-to-workspace-${i}"
done
check_cmd_output "switch-to-workspace-10 が <Primary>0" "<Primary>0" \
  gsettings get org.gnome.desktop.wm.keybindings switch-to-workspace-10
check_cmd_output "move-to-workspace-10 が <Primary><Shift>0" "<Primary><Shift>0" \
  gsettings get org.gnome.desktop.wm.keybindings move-to-workspace-10

# Auto Move Windows
AUTO_MOVE_UUID="auto-move-windows@gnome-shell-extensions.gcampax.github.com"
check_dir "/usr/share/gnome-shell/extensions/${AUTO_MOVE_UUID}"
check_cmd_output "enabled-extensions に Auto Move Windows がある" "$AUTO_MOVE_UUID" \
  gsettings get org.gnome.shell enabled-extensions
check_cmd_output "ブラウザ (Brave) がワークスペース 1" "brave-browser.desktop:1" \
  gsettings get org.gnome.shell.extensions.auto-move-windows application-list
check_cmd_output "ターミナル (Ghostty) がワークスペース 6" "com.mitchellh.ghostty.desktop:6" \
  gsettings get org.gnome.shell.extensions.auto-move-windows application-list
check_cmd_output "Zoom がワークスペース 8" "Zoom.desktop:8" \
  gsettings get org.gnome.shell.extensions.auto-move-windows application-list
check_cmd_output "Discord がワークスペース 9" "discord.desktop:9" \
  gsettings get org.gnome.shell.extensions.auto-move-windows application-list

# enabled-extensions を書くファイルは 1 つだけ (モジュール間の上書き事故を防ぐ)
check "enabled-extensions を定義する local.d ファイルは 1 つだけ" \
  bash -c "[ \"\$(grep -l 'enabled-extensions' /etc/dconf/db/local.d/* 2>/dev/null | wc -l)\" -eq 1 ]"

assert_exit
