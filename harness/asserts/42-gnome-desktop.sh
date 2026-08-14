#!/usr/bin/env bash
# Mac 風デスクトップ挙動 (スクリーンショット / トラックパッド / Quick Look) の検証。
set -uo pipefail
# shellcheck source=harness/asserts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# スクリーンショット: macOS と同じ指使い
check_cmd_output "Alt+Shift+3 が画面全体のスクリーンショット" "<Alt><Shift>3" \
  gsettings get org.gnome.shell.keybindings screenshot
check_cmd_output "Alt+Shift+4 が撮影パネル" "<Alt><Shift>4" \
  gsettings get org.gnome.shell.keybindings show-screenshot-ui
check_cmd_output "Alt+Shift+5 が撮影パネル" "<Alt><Shift>5" \
  gsettings get org.gnome.shell.keybindings show-screenshot-ui

# Print キーの既定割当を消していないこと
check_cmd_output "Print キーの既定割当が残っている" "'Print'" \
  gsettings get org.gnome.shell.keybindings show-screenshot-ui
check_cmd_output "Shift+Print の既定割当が残っている" "<Shift>Print" \
  gsettings get org.gnome.shell.keybindings screenshot

# トラックパッド
check_cmd_output "タップでクリックが有効" "^true$" \
  gsettings get org.gnome.desktop.peripherals.touchpad tap-to-click
check_cmd_output "2 本指で右クリック (click-method=fingers)" "fingers" \
  gsettings get org.gnome.desktop.peripherals.touchpad click-method
check_cmd_output "タップしてドラッグが有効" "^true$" \
  gsettings get org.gnome.desktop.peripherals.touchpad tap-and-drag
check_cmd_output "ナチュラルスクロールが有効" "^true$" \
  gsettings get org.gnome.desktop.peripherals.touchpad natural-scroll

# Quick Look 相当
check "gnome-sushi が導入済み" \
  bash -c "dpkg-query -W -f='\${Status}' gnome-sushi 2>/dev/null | grep -q '^install ok installed$'"
check "sushi の実体がある" \
  bash -c "test -x /usr/libexec/sushi || test -x /usr/bin/sushi || ls /usr/libexec/sushi* >/dev/null 2>&1"

assert_exit
