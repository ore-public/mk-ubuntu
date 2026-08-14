#!/usr/bin/env bash
#
# F4. ワークスペース設定
#
# gsettings の羅列ではなく dconf のシステム既定値
# (/etc/dconf/profile/user + /etc/dconf/db/local.d/ + dconf update) で
# 全ユーザーの既定にする。ユーザーは後から GUI で変更できる。
#
# - 固定ワークスペース 10 個
# - Ctrl+1 〜 Ctrl+0 でワークスペース 1 〜 10 へ移動
# - Ctrl+Shift+1 〜 Ctrl+Shift+0 でウィンドウをワークスペース N へ移動
# - Auto Move Windows 拡張を有効化し、Ghostty→WS1 / Brave→WS2 を既定にする
#
set -euo pipefail

MODULE_NAME="40-gnome-workspaces"
# shellcheck source=lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

WORKSPACE_COUNT=10
DCONF_WORKSPACES_FILE="${DCONF_DB_DIR}/40-workspaces"

# Auto Move Windows は gnome-shell-extensions パッケージに同梱されている
AUTO_MOVE_UUID="auto-move-windows@gnome-shell-extensions.gcampax.github.com"
AUTO_MOVE_DIR="/usr/share/gnome-shell/extensions/${AUTO_MOVE_UUID}"

# アプリ (desktop ファイル名) → ワークスペース番号 の既定割当。
# 変更方法は README を参照。
#
# Discord と Zoom は amd64 でしか導入されないが、未導入のアプリを並べておいても
# 実害はない (該当するウィンドウが出てこないだけ) ので、両アーキで同じ値にする。
#
# 初回ウィザードは Ghostty で開くが、ワークスペース 6 へ飛ばされると
# ログイン直後に見えなくなってしまう。そのため専用の WM_CLASS を付けて
# ここの対象から外している (files/skel/.config/autostart を参照)。
AUTO_MOVE_LIST="['brave-browser.desktop:1', 'com.mitchellh.ghostty.desktop:6', 'Zoom.desktop:8', 'discord.desktop:9']"

# Ctrl+N / Ctrl+Shift+N のキーバインド定義を組み立てる。
# ワークスペース 10 には Ctrl+0 を割り当てる (数字キーの並び順に合わせる)。
render_keybindings() {
  local i key
  for i in $(seq 1 "$WORKSPACE_COUNT"); do
    key=$((i % 10))
    printf "switch-to-workspace-%d=['<Primary>%d']\n" "$i" "$key"
  done
  for i in $(seq 1 "$WORKSPACE_COUNT"); do
    key=$((i % 10))
    printf "move-to-workspace-%d=['<Primary><Shift>%d']\n" "$i" "$key"
  done
}

write_dconf_defaults() {
  ensure_dconf_profile

  {
    cat <<EOF
# 固定ワークスペース ${WORKSPACE_COUNT} 個と、その移動キーバインド。
[org/gnome/mutter]
dynamic-workspaces=false

[org/gnome/desktop/wm/preferences]
num-workspaces=${WORKSPACE_COUNT}

[org/gnome/desktop/wm/keybindings]
EOF
    render_keybindings
    cat <<EOF

# Auto Move Windows: アプリごとの起動先ワークスペース。
# 書式は '<desktop ファイル名>:<ワークスペース番号>'。
[org/gnome/shell/extensions/auto-move-windows]
application-list=${AUTO_MOVE_LIST}
EOF
  } | write_file "$DCONF_WORKSPACES_FILE" 0644
}

main() {
  require_root

  [ -d "$AUTO_MOVE_DIR" ] ||
    warn "Auto Move Windows 拡張が見つかりません (${AUTO_MOVE_DIR})。gnome-shell-extensions を確認してください。"

  write_dconf_defaults
  dconf_enable_extension "$AUTO_MOVE_UUID"
  dconf_update

  log "ワークスペース数: ${WORKSPACE_COUNT} (固定)"
  log "Auto Move Windows の割当:"
  log "  ブラウザ (Brave)   -> ワークスペース 1"
  log "  ターミナル (Ghostty) -> ワークスペース 6"
  log "  Zoom               -> ワークスペース 8"
  log "  Discord            -> ワークスペース 9"
  log "反映にはログアウトとログインが必要です。"
}

main "$@"
