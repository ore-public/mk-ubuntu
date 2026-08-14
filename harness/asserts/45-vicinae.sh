#!/usr/bin/env bash
# ランチャー Vicinae の検証。
set -uo pipefail
# shellcheck source=harness/asserts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

VICINAE_VERSION="v0.25.0"
VICINAE_HOTKEY="F12"

check_dir /opt/vicinae
check "AppRun が実行可能" test -x /opt/vicinae/AppRun
check "ラッパーが実行可能" test -x /usr/local/bin/vicinae
check_cmd_output "Vicinae のバージョンが ${VICINAE_VERSION}" "$VICINAE_VERSION" \
  /usr/local/bin/vicinae version

# AppImage の中身は libOpenGL.so.0 を要求する
check "共有ライブラリがすべて解決できる" \
  bash -c "! ldd /opt/vicinae/usr/bin/vicinae-server 2>/dev/null | grep -q 'not found'"
check "libopengl0 が導入済み" \
  bash -c "dpkg-query -W -f='\${Status}' libopengl0 2>/dev/null | grep -q '^install ok installed$'"

# systemd ユーザーサービス
check_file /etc/systemd/user/vicinae.service
check "default.target.wants に symlink がある" \
  bash -c "[ \"\$(readlink /etc/systemd/user/default.target.wants/vicinae.service)\" = /etc/systemd/user/vicinae.service ]"

# 呼び出しキー (カスタムキーバインド)
check_cmd_output "custom-keybindings に 2 件登録されている (ターミナルとランチャー)" \
  "custom0.*custom1" \
  gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings

found_terminal=0
found_vicinae=0
for slot in 0 1 2 3; do
  path="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom${slot}/"
  schema="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:${path}"
  cmd="$(gsettings get "$schema" command 2>/dev/null || true)"
  key="$(gsettings get "$schema" binding 2>/dev/null || true)"
  case "$cmd" in
    *xdg-terminal-exec*)
      case "$key" in *"<Primary><Alt>t"*) found_terminal=1 ;; esac
      ;;
    *"vicinae toggle"*)
      case "$key" in *"${VICINAE_HOTKEY}"*) found_vicinae=1 ;; esac
      ;;
  esac
done

if [ "$found_terminal" -eq 1 ]; then
  pass "Ctrl+Alt+T のターミナル起動が残っている (登録簿が上書きされていない)"
else
  fail "Ctrl+Alt+T のターミナル起動が残っている (登録簿が上書きされていない)"
fi

if [ "$found_vicinae" -eq 1 ]; then
  pass "${VICINAE_HOTKEY} で vicinae toggle が起動する"
else
  fail "${VICINAE_HOTKEY} で vicinae toggle が起動する"
  diag "登録済みのカスタムキーバインドを確認してください。"
fi

# 実際にサーバーが動いていて応答すること
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if systemctl --user is-active vicinae.service >/dev/null 2>&1; then
  pass "vicinae.service が active である"
  check "vicinae ping が通る" /usr/local/bin/vicinae ping
else
  fail "vicinae.service が active である"
  systemctl --user status vicinae.service --no-pager 2>&1 | head -n 15 |
    while IFS= read -r l; do diag "$l"; done
fi

assert_exit
