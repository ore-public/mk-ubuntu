#!/usr/bin/env bash
#
# Mac 風のデスクトップ挙動
#
# - スクリーンショットを macOS と同じ指使い (Alt+Shift+3/4/5) で起動できるようにする
# - トラックパッドをタップでクリック / 2 本指で右クリックにする
#
# どちらも dconf のシステム既定値で全ユーザーの既定にする。
# ユーザーは「設定」アプリから後で変更でき、その値が優先される。
#
set -euo pipefail

MODULE_NAME="42-gnome-desktop"
# shellcheck source=lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

DCONF_DESKTOP_FILE="${DCONF_DB_DIR}/42-gnome-desktop"

# macOS との対応:
#   Cmd+Shift+3 → 画面全体を撮ってそのまま保存      = screenshot
#   Cmd+Shift+4 → 範囲選択                          = show-screenshot-ui
#   Cmd+Shift+5 → 撮影パネル (範囲/ウィンドウ/録画) = show-screenshot-ui
# GNOME には「範囲選択を即開始する」専用のアクションがなく、範囲選択も撮影パネルの
# 中で行うため、4 と 5 は同じ show-screenshot-ui を指す。
# Print キーの既定割当は消さずに残す。
write_dconf_defaults() {
  ensure_dconf_profile

  write_file "$DCONF_DESKTOP_FILE" 0644 <<'EOF'
# macOS と同じ指使いでスクリーンショットを撮る。
# Print キーの既定割当 (Print / Shift+Print / Alt+Print) はそのまま残している。
[org/gnome/shell/keybindings]
screenshot=['<Shift>Print', '<Alt><Shift>3']
show-screenshot-ui=['Print', '<Alt><Shift>4', '<Alt><Shift>5']
screenshot-window=['<Alt>Print']

# トラックパッドの Mac 風設定。
# tap-to-click   : 1 本指のタップでクリック
# click-method   : 'fingers' = 2 本指のタップ / クリックで右クリック
# tap-and-drag   : タップしてそのままドラッグ
# natural-scroll : 指の動きと画面の動きを一致させる (macOS の「ナチュラル」)
[org/gnome/desktop/peripherals/touchpad]
tap-to-click=true
click-method='fingers'
tap-and-drag=true
natural-scroll=true
EOF
}

main() {
  require_root

  write_dconf_defaults
  dconf_update

  # Quick Look 相当 (Nautilus でスペースキーを押すとプレビュー) は
  # gnome-sushi パッケージが提供する。導入は 10-packages.sh。
  if dpkg-query -W -f='${Status}' gnome-sushi 2>/dev/null | grep -q "^install ok installed$"; then
    log "gnome-sushi 導入済み: Files でスペースキーのプレビューが使えます"
  else
    warn "gnome-sushi が導入されていません。先に 10-packages.sh を実行してください。"
  fi

  log "スクリーンショット: Alt+Shift+3 (全画面) / Alt+Shift+4, Alt+Shift+5 (撮影パネル)"
  log "トラックパッド: タップでクリック、2 本指で右クリック"
  log "反映にはログアウトとログインが必要です。"
}

main "$@"
