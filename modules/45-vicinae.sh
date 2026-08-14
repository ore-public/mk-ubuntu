#!/usr/bin/env bash
#
# ランチャー Vicinae (macOS の Spotlight / Alfred 相当)
#
# 配布形式は AppImage のみ (amd64 / arm64 とも)。AppImage をそのまま実行すると
# FUSE を要求するため、--appimage-extract で中身を取り出して /opt/vicinae に置き、
# /usr/local/bin/vicinae からラッパーで呼ぶ。FUSE 不要で起動が速い。
#
# サーバー常駐が必要なので systemd ユーザーサービスにする (xremap と同じ方式)。
# 呼び出しキーは dconf のカスタムキーバインドで設定する。
#
set -euo pipefail

MODULE_NAME="45-vicinae"
# shellcheck source=lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

VICINAE_VERSION="v0.25.0"
VICINAE_BASE_URL="https://github.com/vicinaehq/vicinae/releases/download/${VICINAE_VERSION}"
VICINAE_ASSET_AMD64="Vicinae-x86_64.AppImage"
VICINAE_SHA256_AMD64="49f19f685302beffa5eff1e73b3ae8012cd4bb5cba9dea6fb86397a2a20f06e8"
VICINAE_ASSET_ARM64="Vicinae-aarch64.AppImage"
VICINAE_SHA256_ARM64="4c39dfbd21cc1021900a24f0d1f568d24c6ca37fe908276a9e042fb570ea863c"

VICINAE_DIR="/opt/vicinae"
VICINAE_BIN="/usr/local/bin/vicinae"
VICINAE_VERSION_STAMP="${VICINAE_DIR}/.installed-version"
CACHE_DIR="/var/cache/mk-ubuntu"

SYSTEMD_USER_UNIT="/etc/systemd/user/vicinae.service"
SYSTEMD_USER_WANTS="/etc/systemd/user/default.target.wants/vicinae.service"

# 呼び出しキー。変更方法は README の「設計判断」節を参照。
VICINAE_HOTKEY="F12"

# クリップボード履歴とウィンドウ管理の API を Vicinae に渡す GNOME 拡張。
# これがないと Vicinae はクリップボード履歴を扱えない。
# extensions.gnome.org の配布物 (GNOME 46-50 対応) を同梱している。
VICINAE_EXT_UUID="vicinae@dagimg-dot"
VICINAE_EXT_ZIP="${REPO_ROOT}/files/gnome-extensions/vicinae@dagimg-dot.v1.7.0.shell-extension.zip"
VICINAE_EXT_DIR="/usr/share/gnome-shell/extensions/${VICINAE_EXT_UUID}"

install_vicinae() {
  if [ -f "$VICINAE_VERSION_STAMP" ] &&
    [ "$(cat "$VICINAE_VERSION_STAMP")" = "$VICINAE_VERSION" ] &&
    [ -x "${VICINAE_DIR}/AppRun" ]; then
    log "変更なし: ${VICINAE_DIR} (${VICINAE_VERSION})"
    return 0
  fi

  local asset sha cached workdir
  asset="$(pick_arch "$VICINAE_ASSET_AMD64" "$VICINAE_ASSET_ARM64")"
  sha="$(pick_arch "$VICINAE_SHA256_AMD64" "$VICINAE_SHA256_ARM64")"
  cached="${CACHE_DIR}/vicinae-${VICINAE_VERSION}-${asset}"

  install -d "$CACHE_DIR"
  download_verify "${VICINAE_BASE_URL}/${asset}" "$sha" "$cached"
  chmod 0755 "$cached"

  workdir="$(mktemp -d)"
  log "AppImage を展開します"
  # --appimage-extract は AppImage のランタイム自身が処理するので FUSE は要らない
  ( cd "$workdir" && "$cached" --appimage-extract >/dev/null ) ||
    { rm -rf "$workdir"; die "AppImage の展開に失敗しました。"; }

  [ -x "${workdir}/squashfs-root/AppRun" ] ||
    { rm -rf "$workdir"; die "展開結果に AppRun がありません。"; }

  rm -rf "$VICINAE_DIR"
  install -d "$VICINAE_DIR"
  cp -a "${workdir}/squashfs-root/." "${VICINAE_DIR}/"
  chmod -R a+rX "$VICINAE_DIR"
  rm -rf "$workdir"

  printf '%s\n' "$VICINAE_VERSION" >"$VICINAE_VERSION_STAMP"
  log "配置: ${VICINAE_DIR}"
}

install_wrapper() {
  # AppRun は自分の位置から APPDIR を決めるので、symlink ではなくラッパーで呼ぶ
  write_file "$VICINAE_BIN" 0755 <<EOF
#!/bin/sh
# Vicinae ランチャー (${VICINAE_DIR} に展開した AppImage を呼ぶ)
exec ${VICINAE_DIR}/AppRun "\$@"
EOF
}

install_systemd_unit() {
  install_file "${REPO_ROOT}/files/systemd/vicinae.service" "$SYSTEMD_USER_UNIT" 0644

  install -d "$(dirname "$SYSTEMD_USER_WANTS")"
  if [ "$(readlink "$SYSTEMD_USER_WANTS" 2>/dev/null || true)" = "$SYSTEMD_USER_UNIT" ]; then
    log "変更なし: $SYSTEMD_USER_WANTS"
  else
    ln -sfn "$SYSTEMD_USER_UNIT" "$SYSTEMD_USER_WANTS"
    log "配置: ${SYSTEMD_USER_WANTS} -> ${SYSTEMD_USER_UNIT}"
  fi

  systemctl daemon-reload || true
}

install_gnome_extension() {
  [ -f "$VICINAE_EXT_ZIP" ] || die "同梱の GNOME 拡張が見つかりません: $VICINAE_EXT_ZIP"

  local staged
  staged="$(mktemp -d)"
  unzip -q -o "$VICINAE_EXT_ZIP" -d "$staged"

  # この拡張は gschema を持つ。extensions.gnome.org 経由の導入では
  # インストーラがコンパイルするので、手で置く場合は自分でコンパイルする。
  # (gschemas.compiled が無いと拡張の設定読み込みで失敗する)
  if [ -d "${staged}/schemas" ]; then
    glib-compile-schemas "${staged}/schemas" ||
      { rm -rf "$staged"; die "GNOME 拡張の gschema のコンパイルに失敗しました。"; }
  fi

  if [ -d "$VICINAE_EXT_DIR" ] && diff -r -q "$staged" "$VICINAE_EXT_DIR" >/dev/null 2>&1; then
    log "変更なし: $VICINAE_EXT_DIR"
  else
    rm -rf "$VICINAE_EXT_DIR"
    install -d "$VICINAE_EXT_DIR"
    cp -a "${staged}/." "$VICINAE_EXT_DIR/"
    chmod -R a+rX "$VICINAE_EXT_DIR"
    log "配置: $VICINAE_EXT_DIR"
  fi
  rm -rf "$staged"

  local shell_major
  if command -v gnome-shell >/dev/null 2>&1; then
    shell_major="$(gnome-shell --version 2>/dev/null | grep -oE '[0-9]+' | head -n 1)"
    if [ -n "$shell_major" ] &&
      ! grep -q "\"${shell_major}\"" "${VICINAE_EXT_DIR}/metadata.json"; then
      warn "同梱の Vicinae 拡張は GNOME ${shell_major} に対応していない可能性があります。"
    fi
  fi

  dconf_enable_extension "$VICINAE_EXT_UUID"
}

set_hotkey() {
  dconf_set_custom_keybinding "vicinae" "Vicinae" "vicinae toggle" "$VICINAE_HOTKEY"
  dconf_update
}

main() {
  require_root

  # AppImage の中身は libOpenGL.so.0 を要求する (10-packages.sh で導入)
  if ! ldconfig -p 2>/dev/null | grep -q "libOpenGL.so.0"; then
    warn "libOpenGL.so.0 が見つかりません。先に 10-packages.sh を実行してください。"
  fi

  install_vicinae
  install_wrapper
  install_systemd_unit
  install_gnome_extension
  set_hotkey

  log "Vicinae ${VICINAE_VERSION}: $("$VICINAE_BIN" version 2>/dev/null | head -n 1 || echo 'バージョン取得失敗')"
  log "呼び出しキー: ${VICINAE_HOTKEY}"
  log "クリップボード履歴: GNOME 拡張 ${VICINAE_EXT_UUID} を有効化しました"
  log "反映にはログアウトとログインが必要です。"
}

main "$@"
