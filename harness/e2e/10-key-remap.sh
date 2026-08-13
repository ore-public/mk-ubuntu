#!/usr/bin/env bash
#
# レベル 3: 実キー入力の E2E テスト。
#
# ydotool でカーネルにキーイベントを注入し、xremap が出力する仮想デバイスを
# probe.py で読み取って、変換結果が期待どおりかを確認する。
#
# タイミング起因で不安定になりうるため、vmtest 側で 1 回リトライし、
# 失敗しても vmtest full の終了コードには含めない (警告扱い)。
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="${SCRIPT_DIR}/probe.py"

# Linux の入力イベントコード (include/uapi/linux/input-event-codes.h)
KEY_C=46
KEY_P=25
KEY_UP=103
KEY_LEFTCTRL=29
KEY_LEFTALT=56
KEY_CAPSLOCK=58

FAILURES=0

info() { printf '# %s\n' "$*"; }
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

require() {
  command -v "$1" >/dev/null 2>&1 || {
    info "必要なコマンドがありません: $1"
    exit 77
  }
}

require ydotool
require python3

# ydotoold (ydotool のバックエンド) を用意する
export YDOTOOL_SOCKET="${YDOTOOL_SOCKET:-/tmp/.ydotool_socket}"
if ! sudo -n test -S "$YDOTOOL_SOCKET"; then
  info "ydotoold を起動します"
  sudo -n sh -c "nohup ydotoold --socket-path='${YDOTOOL_SOCKET}' --socket-own=$(id -u):$(id -g) >/tmp/ydotoold.log 2>&1 &"
  sleep 2
fi

if ! sudo -n test -S "$YDOTOOL_SOCKET"; then
  info "ydotoold のソケットが作られませんでした。/tmp/ydotoold.log を確認してください。"
  exit 77
fi

# run_case <説明> <注入するキー列> <期待するキーコード>
# 注入するキー列は ydotool key の引数そのまま (例: "58:1 58:0")
run_case() {
  local desc="$1" keys="$2" expect="$3" out rc

  out="$(mktemp)"
  # リダイレクト先は呼び出し側ユーザーが作った一時ファイルなので、
  # sudo がリダイレクトに効かなくて問題ない
  # shellcheck disable=SC2024
  sudo -n python3 "$PROBE" 4 xremap >"$out" 2>/tmp/probe.err &
  local probe_pid=$!
  sleep 1.5

  # shellcheck disable=SC2086
  ydotool key $keys >/dev/null 2>&1 || info "ydotool key が失敗しました: ${keys}"

  wait "$probe_pid"
  rc=$?

  if [ "$rc" -eq 2 ]; then
    info "xremap の仮想デバイスが見つかりません。xremap.service の状態を確認してください。"
    fail "$desc"
    rm -f "$out"
    return 0
  fi

  if awk -v want="$expect" '$1 == want && $2 == 1 { found = 1 } END { exit found ? 0 : 1 }' "$out"; then
    pass "$desc"
  else
    fail "$desc"
    info "期待したキーコード ${expect} の押下が観測されませんでした。観測したイベント:"
    sort -u "$out" | head -n 20 | while IFS= read -r l; do info "  $l"; done
  fi
  rm -f "$out"
}

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"

# keymap の変換は application 条件 (ターミナルを除外) の評価を伴うため、
# 非ターミナルのウィンドウにフォーカスがないと 1 つも適用されない。
# そこでテスト用のウィンドウを開いてフォーカスを作る。
WINDOW_UNIT="e2e-focus-window"

focused_wm_class() {
  gdbus call --session --dest org.gnome.Shell \
    --object-path /com/k0kubun/Xremap \
    --method com.k0kubun.Xremap.ActiveWindow 2>/dev/null
}

open_focus_window() {
  local app
  for app in gnome-text-editor gnome-calculator gnome-disks; do
    command -v "$app" >/dev/null 2>&1 || continue
    systemd-run --user --unit="$WINDOW_UNIT" --collect "$app" >/dev/null 2>&1 || continue
    local attempt=0
    while [ "$attempt" -lt 10 ]; do
      attempt=$((attempt + 1))
      sleep 2
      case "$(focused_wm_class)" in
        *wm_class*ghostty* | *wm_class*Ptyxis*) ;;
        *wm_class*) info "フォーカス用ウィンドウ: $(focused_wm_class)"; return 0 ;;
      esac
    done
    systemd-run --user --unit="$WINDOW_UNIT" --collect true >/dev/null 2>&1 || true
  done
  return 1
}

# trap から呼ばれる
# shellcheck disable=SC2329
close_focus_window() {
  systemctl --user stop "${WINDOW_UNIT}.service" >/dev/null 2>&1 || true
}
trap close_focus_window EXIT

info "xremap のキー変換を実キー入力で確認します"

# modmap による変換はフォーカス状態に依存しない
run_case "CapsLock が Ctrl になる" \
  "${KEY_CAPSLOCK}:1 ${KEY_CAPSLOCK}:0" "$KEY_LEFTCTRL"

if open_focus_window; then
  run_case "Ctrl-p が Up になる" \
    "${KEY_LEFTCTRL}:1 ${KEY_P}:1 ${KEY_P}:0 ${KEY_LEFTCTRL}:0" "$KEY_UP"

  run_case "Alt-c が Ctrl-c になる (非ターミナル)" \
    "${KEY_LEFTALT}:1 ${KEY_C}:1 ${KEY_C}:0 ${KEY_LEFTALT}:0" "$KEY_LEFTCTRL"
else
  info "非ターミナルのウィンドウを開けなかったため、keymap の確認をスキップします。"
  info "実機の手動確認に回してください。"
fi

info "失敗数: ${FAILURES}"
exit "$FAILURES"
