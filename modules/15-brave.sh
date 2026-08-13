#!/usr/bin/env bash
#
# F1.5. Brave ブラウザ
#
# Brave 公式 apt リポジトリ (amd64 / arm64 両対応) から brave-browser を導入し、
# システム既定ブラウザにする。
# 本リポジトリで外部 apt リポジトリを追加するのはこのモジュールだけ。
# apt-key は Ubuntu 26.04 に存在しないため keyring 方式のみを使う。
#
set -euo pipefail

MODULE_NAME="15-brave"
# shellcheck source=lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

BRAVE_KEYRING_URL="https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg"
BRAVE_KEYRING_PATH="/etc/apt/keyrings/brave-browser-archive-keyring.gpg"
BRAVE_REPO_URL="https://brave-browser-apt-release.s3.brave.com/"
BRAVE_SOURCES_PATH="/etc/apt/sources.list.d/brave-browser-release.sources"
BRAVE_DESKTOP="brave-browser.desktop"

# Brave は自動更新のためリポジトリのローリング配信のみを提供しており、
# 個別バージョンの固定 URL を公開していない。したがってここではバージョン固定せず、
# apt のリポジトリ署名 (signed-by) を信頼の根拠とする。README の設計判断を参照。

setup_repository() {
  install -d -m 0755 /etc/apt/keyrings

  if [ -f "$BRAVE_KEYRING_PATH" ]; then
    log "変更なし: $BRAVE_KEYRING_PATH"
  else
    log "Brave の署名鍵を取得します"
    local tmp
    tmp="$(mktemp)"
    curl -fsSL --retry 3 --retry-delay 2 -o "$tmp" "$BRAVE_KEYRING_URL" ||
      { rm -f "$tmp"; die "Brave の署名鍵の取得に失敗しました。"; }
    install -m 0644 "$tmp" "$BRAVE_KEYRING_PATH"
    rm -f "$tmp"
    log "配置: $BRAVE_KEYRING_PATH"
  fi

  # APT 3 系の deb822 形式で記述する。
  local before_hash=""
  [ -f "$BRAVE_SOURCES_PATH" ] && before_hash="$(sha256sum "$BRAVE_SOURCES_PATH" | cut -d' ' -f1)"

  write_file "$BRAVE_SOURCES_PATH" 0644 <<EOF
Types: deb
URIs: ${BRAVE_REPO_URL}
Suites: stable
Components: main
Architectures: amd64 arm64
Signed-By: ${BRAVE_KEYRING_PATH}
EOF

  local after_hash
  after_hash="$(sha256sum "$BRAVE_SOURCES_PATH" | cut -d' ' -f1)"
  if [ "$before_hash" != "$after_hash" ]; then
    # リポジトリ定義が変わったときだけ apt update を強制する
    APT_UPDATED=0
  fi
}

# 既定ブラウザをシステムレベルで設定する。
# 採用機構: /etc/xdg/mimeapps.list (XDG_CONFIG_DIRS 上のシステム既定) +
# Debian の update-alternatives。README の設計判断を参照。
set_default_browser() {
  write_file /etc/xdg/mimeapps.list 0644 <<EOF
[Default Applications]
x-scheme-handler/http=${BRAVE_DESKTOP}
x-scheme-handler/https=${BRAVE_DESKTOP}
x-scheme-handler/about=${BRAVE_DESKTOP}
x-scheme-handler/unknown=${BRAVE_DESKTOP}
text/html=${BRAVE_DESKTOP}
application/xhtml+xml=${BRAVE_DESKTOP}
EOF

  local alt
  for alt in x-www-browser gnome-www-browser; do
    if update-alternatives --list "$alt" 2>/dev/null | grep -qx /usr/bin/brave-browser; then
      update-alternatives --set "$alt" /usr/bin/brave-browser >/dev/null
      log "update-alternatives: ${alt} -> /usr/bin/brave-browser"
    else
      log "update-alternatives の ${alt} に brave-browser の候補がないためスキップします"
    fi
  done

  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
  fi
}

main() {
  require_root

  setup_repository
  apt_install brave-browser
  set_default_browser

  log "導入済みバージョン: $(brave-browser --version 2>/dev/null || echo '取得失敗')"
  log "Firefox は削除していません (公式構成からの逸脱を最小化するため)。"
}

main "$@"
