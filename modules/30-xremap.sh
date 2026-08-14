#!/usr/bin/env bash
#
# F3. xremap による Mac 風キー操作
#
# - GitHub Releases のビルド済みバイナリ (gnome feature 版) を /usr/local/bin に置く
# - xremap 用 GNOME 拡張を /usr/share/gnome-shell/extensions に置き、dconf で有効化する
#   (26.04 は Wayland 専用なので、この拡張がないとアプリ別リマップが機能しない)
# - uinput / input グループの権限を整える
# - systemd user unit を全ユーザー有効化する
#
set -euo pipefail

MODULE_NAME="30-xremap"
# shellcheck source=lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

XREMAP_VERSION="v0.15.10"
XREMAP_BASE_URL="https://github.com/xremap/xremap/releases/download/${XREMAP_VERSION}"
# アーキごとの配布物とチェックサム (gnome feature 版)
XREMAP_ASSET_AMD64="xremap-linux-x86_64-gnome.zip"
XREMAP_SHA256_AMD64="4af9d846e16a41a9e11fe2bea678fc7e8739bde78ca6a020f8529614f30c82cb"
XREMAP_ASSET_ARM64="xremap-linux-aarch64-gnome.zip"
XREMAP_SHA256_ARM64="48a5a8a793c7acd21974747c30048c38d7a215c42decac8003c5b1ed4ff94705"

XREMAP_BIN="/usr/local/bin/xremap"
XREMAP_CACHE_DIR="/var/cache/mk-ubuntu"

# GNOME 拡張はリポジトリに同梱している (extensions.gnome.org 版 v15 / GNOME 45-50 対応)
XREMAP_EXT_UUID="xremap@k0kubun.com"
XREMAP_EXT_ZIP="${REPO_ROOT}/files/gnome-extensions/xremap@k0kubun.com.v15.shell-extension.zip"
XREMAP_EXT_DIR="/usr/share/gnome-shell/extensions/${XREMAP_EXT_UUID}"

UDEV_RULE="/etc/udev/rules.d/99-input.rules"
SYSTEMD_USER_UNIT="/etc/systemd/user/xremap.service"
SYSTEMD_USER_WANTS="/etc/systemd/user/default.target.wants/xremap.service"

install_binary() {
  local asset sha url zip extract_dir
  asset="$(pick_arch "$XREMAP_ASSET_AMD64" "$XREMAP_ASSET_ARM64")"
  sha="$(pick_arch "$XREMAP_SHA256_AMD64" "$XREMAP_SHA256_ARM64")"
  url="${XREMAP_BASE_URL}/${asset}"
  zip="${XREMAP_CACHE_DIR}/${asset}"

  # 既に同じバージョンが入っていれば何もしない
  if [ -x "$XREMAP_BIN" ] &&
    "$XREMAP_BIN" --version 2>/dev/null | grep -qF "${XREMAP_VERSION#v}"; then
    log "変更なし: ${XREMAP_BIN} ($("$XREMAP_BIN" --version 2>/dev/null))"
    return 0
  fi

  install -d "$XREMAP_CACHE_DIR"
  download_verify "$url" "$sha" "$zip"

  extract_dir="$(mktemp -d)"
  unzip -q -o "$zip" -d "$extract_dir"
  [ -f "${extract_dir}/xremap" ] || { rm -rf "$extract_dir"; die "zip に xremap が入っていません: $zip"; }
  install -m 0755 "${extract_dir}/xremap" "$XREMAP_BIN"
  rm -rf "$extract_dir"
  log "配置: ${XREMAP_BIN} ($("$XREMAP_BIN" --version 2>/dev/null || echo 'バージョン取得失敗'))"
}

install_gnome_extension() {
  [ -f "$XREMAP_EXT_ZIP" ] || die "同梱の GNOME 拡張が見つかりません: $XREMAP_EXT_ZIP"

  local staged
  staged="$(mktemp -d)"
  unzip -q -o "$XREMAP_EXT_ZIP" -d "$staged"

  if [ -d "$XREMAP_EXT_DIR" ] && diff -r -q "$staged" "$XREMAP_EXT_DIR" >/dev/null 2>&1; then
    log "変更なし: $XREMAP_EXT_DIR"
  else
    install -d "$XREMAP_EXT_DIR"
    cp -a "${staged}/." "$XREMAP_EXT_DIR/"
    chmod -R a+rX "$XREMAP_EXT_DIR"
    log "配置: $XREMAP_EXT_DIR"
  fi
  rm -rf "$staged"

  # GNOME Shell のバージョンと拡張の対応を確認する (合わないと読み込まれない)
  local shell_major
  if command -v gnome-shell >/dev/null 2>&1; then
    shell_major="$(gnome-shell --version 2>/dev/null | grep -oE '[0-9]+' | head -n 1)"
    if [ -n "$shell_major" ] &&
      ! grep -q "\"${shell_major}\"" "${XREMAP_EXT_DIR}/metadata.json"; then
      warn "同梱の xremap 拡張は GNOME ${shell_major} に対応していない可能性があります。"
    fi
  fi

  dconf_enable_extension "$XREMAP_EXT_UUID"
  dconf_update
}

setup_input_permissions() {
  # uinput デバイスを input グループから触れるようにする
  write_file "$UDEV_RULE" 0644 <<'EOF'
KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"
EOF

  # 新規ユーザーを既定で input グループに入れる
  # (既存ユーザーへの付与は 70-existing-users.sh が行う)
  add_extra_group input

  # ルール追加後に既存ノードへ反映する (VM / 実機どちらでも必要)
  if command -v udevadm >/dev/null 2>&1; then
    udevadm control --reload-rules >/dev/null 2>&1 || warn "udevadm control --reload-rules に失敗しました。"
    udevadm trigger --subsystem-match=misc --name-match=uinput >/dev/null 2>&1 || true
  fi

}

install_systemd_unit() {
  # ラッパーは config.local.yml の有無を見て引数を組み立てる
  install_file "${REPO_ROOT}/files/bin/xremap-session" /usr/local/bin/xremap-session 0755
  install_file "${REPO_ROOT}/files/systemd/xremap.service" "$SYSTEMD_USER_UNIT" 0644

  # /etc/systemd/user/default.target.wants/ への symlink でシステム全体有効化する。
  # 各ユーザーが systemctl --user enable する必要がない。
  install -d "$(dirname "$SYSTEMD_USER_WANTS")"
  if [ "$(readlink "$SYSTEMD_USER_WANTS" 2>/dev/null || true)" = "$SYSTEMD_USER_UNIT" ]; then
    log "変更なし: $SYSTEMD_USER_WANTS"
  else
    ln -sfn "$SYSTEMD_USER_UNIT" "$SYSTEMD_USER_WANTS"
    log "配置: ${SYSTEMD_USER_WANTS} -> ${SYSTEMD_USER_UNIT}"
  fi

  systemctl daemon-reload || true
}

main() {
  require_root

  install_binary
  install_file "${REPO_ROOT}/files/skel/.config/xremap/config.yml" \
    /etc/skel/.config/xremap/config.yml 0644
  # 個人用の受け皿 (中身はコメントと空リストのひな形)
  install_file "${REPO_ROOT}/files/skel/.config/xremap/config.local.yml" \
    /etc/skel/.config/xremap/config.local.yml 0644
  install_gnome_extension
  setup_input_permissions
  install_systemd_unit

  log "xremap ${XREMAP_VERSION} の設定が完了しました。"
  log "反映にはログアウトとログインが必要です。"
}

main "$@"
