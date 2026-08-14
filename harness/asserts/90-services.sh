#!/usr/bin/env bash
# systemd ユーザーサービスの状態検証。
#
# xremap.service はグラフィカルセッションが立ち上がっているユーザーでのみ active になる。
# 検証 VM は自動ログイン済みなので、そのセッションの systemd に問い合わせる。
set -uo pipefail
# shellcheck source=harness/asserts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

UID_NUM="$(id -u)"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/${UID_NUM}}"
# SSH 経由だとセッションバスのアドレスが渡ってこないので明示する
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"

# xremap のユニットは ~/.config/xremap/config.yml がないと起動しない。
# /etc/skel は新規ユーザーにしか効かないので、既存ユーザーには
# 70-existing-users.sh が配る。まずそれが届いているかを見る。
check_file "${HOME}/.config/xremap/config.yml" \
  "既存ユーザーのホームに xremap の設定が配られている"
check "既存ユーザーが input グループに入っている" \
  bash -c "id -nG | tr ' ' '\n' | grep -qx input"

if [ ! -S "${XDG_RUNTIME_DIR}/systemd/private" ] &&
  ! systemctl --user is-system-running >/dev/null 2>&1; then
  diag "ユーザー systemd に接続できません (グラフィカルセッション未起動の可能性)。"
  fail "ユーザー systemd に接続できる"
  assert_exit
fi

check "xremap.service がユーザー systemd から見えている" \
  bash -c "systemctl --user list-unit-files xremap.service | grep -q xremap"

check_cmd_output "xremap.service が enabled になっている" "enabled|static|generated" \
  bash -c "systemctl --user is-enabled xremap.service 2>&1"

# ExecStartPre の sleep 5 があるため、起動直後は activating のことがある
for _ in 1 2 3 4 5 6; do
  systemctl --user is-active xremap.service >/dev/null 2>&1 && break
  sleep 5
done

if systemctl --user is-active xremap.service >/dev/null 2>&1; then
  pass "xremap.service が active である"
else
  fail "xremap.service が active である"
  systemctl --user status xremap.service --no-pager 2>&1 | head -n 20 |
    while IFS= read -r l; do diag "$l"; done
  journalctl --user -u xremap.service -n 20 --no-pager 2>&1 |
    while IFS= read -r l; do diag "$l"; done
fi

# GNOME Shell の拡張が実際に読み込まれているか (Wayland のアプリ別リマップに必須)。
# WMClass はフォーカス中のウィンドウがないと値を返せず応答しないので、
# 常に JSON 文字列を返す ActiveWindow を使う。
if command -v gdbus >/dev/null 2>&1; then
  if gdbus call --session --dest org.gnome.Shell \
    --object-path /com/k0kubun/Xremap \
    --method com.k0kubun.Xremap.ActiveWindow >/dev/null 2>&1; then
    pass "xremap の GNOME 拡張が D-Bus に応答する"
  else
    fail "xremap の GNOME 拡張が D-Bus に応答する"
    diag "GNOME Shell の再ログインが必要か、拡張が有効化されていない可能性があります。"
    gnome-extensions info xremap@k0kubun.com 2>&1 | head -n 8 |
      while IFS= read -r l; do diag "$l"; done
  fi
fi

# クリップボード履歴の拡張が実際に読み込まれていること
if command -v gnome-extensions >/dev/null 2>&1; then
  check_cmd_output "Vicinae のクリップボード拡張が ACTIVE" "State: ACTIVE" \
    gnome-extensions info "vicinae@dagimg-dot"
fi

# Ubuntu が既定で有効にしている拡張を消していないこと
# (enabled-extensions をシステム既定値で上書きする副作用の確認)
if command -v gnome-extensions >/dev/null 2>&1; then
  check_cmd_output "Ubuntu 標準の Dock 拡張が有効なままである" "ubuntu-dock@ubuntu.com" \
    gnome-extensions list --enabled
fi

assert_exit
