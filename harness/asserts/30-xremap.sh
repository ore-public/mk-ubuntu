#!/usr/bin/env bash
# F3. xremap の検証。
set -uo pipefail
# shellcheck source=harness/asserts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

XREMAP_VERSION="0.15.10"
EXT_UUID="xremap@k0kubun.com"
EXT_DIR="/usr/share/gnome-shell/extensions/${EXT_UUID}"

check "xremap が /usr/local/bin にある" test -x /usr/local/bin/xremap
check_cmd_output "xremap のバージョンが ${XREMAP_VERSION} である" "$XREMAP_VERSION" \
  /usr/local/bin/xremap --version

# GNOME 拡張 (Wayland ではこれがないとアプリ別リマップが機能しない)
check_dir "$EXT_DIR"
check_file "${EXT_DIR}/metadata.json"
check_file "${EXT_DIR}/extension.js"
check_extension_supports_current_shell "${EXT_DIR}/metadata.json" "xremap 拡張"
check_cmd_output "dconf の enabled-extensions に xremap がある" "$EXT_UUID" \
  gsettings get org.gnome.shell enabled-extensions

# uinput / input グループ
check_contains /etc/udev/rules.d/99-input.rules \
  'KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS\+="static_node=uinput"' \
  "udev ルールが uinput を input グループに割り当てている"
check_contains /etc/adduser.conf '^EXTRA_GROUPS=.*\binput\b' \
  "/etc/adduser.conf の EXTRA_GROUPS に input がある"
check_contains /etc/adduser.conf '^ADD_EXTRA_GROUPS=1$' \
  "/etc/adduser.conf の ADD_EXTRA_GROUPS が 1"
check "EXTRA_GROUPS の行が 1 行だけ (追記の重複がない)" \
  bash -c "[ \"\$(grep -c '^EXTRA_GROUPS=' /etc/adduser.conf)\" -eq 1 ]"
check "EXTRA_GROUPS に同じグループが重複していない" \
  bash -c "line=\$(grep -m1 '^EXTRA_GROUPS=' /etc/adduser.conf); v=\${line#EXTRA_GROUPS=}; v=\${v//\\\"/}; [ \"\$(printf '%s' \"\$v\" | tr ' ' '\\n' | sort | uniq -d | wc -l)\" -eq 0 ]"
check "/dev/uinput のグループが input である" \
  bash -c "[ \"\$(stat -c %G /dev/uinput 2>/dev/null)\" = input ]"

# 設定ファイル
check_file /etc/skel/.config/xremap/config.yml
check_contains /etc/skel/.config/xremap/config.yml "CapsLock: Ctrl_L" \
  "xremap 設定に CapsLock -> Ctrl がある"
check_contains /etc/skel/.config/xremap/config.yml "com.mitchellh.ghostty" \
  "xremap 設定がターミナルを除外している"
check_contains /etc/skel/.config/xremap/config.yml "Ctrl-p: Up" \
  "xremap 設定に Ctrl-p -> Up がある"
check_contains /etc/skel/.config/xremap/config.yml "Alt-q: Alt-F4" \
  "xremap 設定に Alt-q -> Alt-F4 がある"

# systemd user unit
check_file /etc/systemd/user/xremap.service
check_contains /etc/systemd/user/xremap.service "^ExecStart=/usr/local/bin/xremap-session %h$" \
  "unit がホームを %h で渡している (ハードコードしていない)"
check "ラッパー xremap-session が実行可能" test -x /usr/local/bin/xremap-session
# 起動後に挿したキーボードにもリマップを効かせるために必須
check_contains /usr/local/bin/xremap-session "\\-\\-watch=device" \
  "ラッパーが --watch=device を付けている"
check_contains /usr/local/bin/xremap-session "config\\.local\\.yml" \
  "ラッパーが個人用の config.local.yml を読み込む"
check_file /etc/skel/.config/xremap/config.local.yml
check "unit に /home/ のハードコードがない" \
  bash -c "! grep -q '/home/' /etc/systemd/user/xremap.service"
check_contains /etc/systemd/user/xremap.service "^Restart=always$" "unit に Restart=always がある"
check_contains /etc/systemd/user/xremap.service "graphical-session.target" \
  "unit が graphical-session.target を待つ"
check "default.target.wants に symlink がある" \
  bash -c "[ \"\$(readlink /etc/systemd/user/default.target.wants/xremap.service)\" = /etc/systemd/user/xremap.service ]"

assert_exit
