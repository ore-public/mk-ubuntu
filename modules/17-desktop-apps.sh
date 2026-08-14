#!/usr/bin/env bash
#
# ベンダー公式の配布物で入れるデスクトップアプリ
#
#   Discord / Zoom / 1Password / Dropbox
#
# いずれも Ubuntu の apt や snap 版ではなく、各社の公式配布物を使う。
#
# **4 つとも公式が amd64 版しか配布していない** (2026-08 時点で確認)。
# arm64 では導入をスキップする。詳しくは docs/development.md の設計判断を参照。
#
# バージョンの扱いは配布形態によって分かれる:
#   Discord / Zoom … 「最新版」の URL しか公開されておらず、かつアプリ自身が
#                     古いバージョンでの起動を拒む。固定せず最新を入れる。
#                     導入済みなら何もしない (更新はアプリ自身が行う)。
#   Dropbox        … バージョン付き URL があるので固定 + SHA256 検証。
#   1Password      … 1Password 公式の apt リポジトリを使う。
#                     パスワード管理ソフトなので更新が届く経路を優先する。
#                     ただし導入後は **パッケージ自身が apt リポジトリ定義を
#                     管理する** ので、こちらは「まだ入っていないときの足場」
#                     だけを用意して、以後は触らない。
#
set -euo pipefail

MODULE_NAME="17-desktop-apps"
# shellcheck source=lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

CACHE_DIR="/var/cache/mk-ubuntu"

# Discord: API が最新版の deb にリダイレクトする
DISCORD_URL="https://discord.com/api/download?platform=linux&format=deb"
DISCORD_PACKAGE="discord"

# Zoom: 最新版の固定 URL
ZOOM_URL="https://zoom.us/client/latest/zoom_amd64.deb"
ZOOM_PACKAGE="zoom"

# Dropbox: バージョン付き URL があるので固定する
DROPBOX_VERSION="2026.05.06"
DROPBOX_URL="https://linux.dropbox.com/packages/ubuntu/dropbox_${DROPBOX_VERSION}_amd64.deb"
DROPBOX_SHA256="f6eaec9fe18ef87ac376fdba276ad7390207e170837f9bbf64d812266961a707"
DROPBOX_PACKAGE="dropbox"

# 1Password: 公式 apt リポジトリ
# 導入時に postinst が下記を行う (deb の postinst で確認済み):
#   - /usr/share/keyrings/1password-archive-keyring.gpg を置く
#   - /etc/apt/sources.list.d/1password.sources を自分の内容で上書きする
#     (先頭に「このファイルは 1Password パッケージが管理する」と書かれる)
# したがって、こちらが用意するのは導入前の足場だけ。
ONEPASSWORD_KEY_URL="https://downloads.1password.com/linux/keys/1password.asc"
ONEPASSWORD_BOOTSTRAP_KEYRING="/etc/apt/keyrings/1password-archive-keyring.gpg"
ONEPASSWORD_REPO_URL="https://downloads.1password.com/linux/debian/amd64"
ONEPASSWORD_SOURCES="/etc/apt/sources.list.d/1password.sources"
ONEPASSWORD_PACKAGE="1password"

package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "^install ok installed$"
}

# install_latest_deb <パッケージ名> <URL> <表示名>
# 「最新版」しか配布されていないもの用。導入済みなら何もしない。
install_latest_deb() {
  local package="$1" url="$2" label="$3" tmp

  if package_installed "$package"; then
    log "変更なし: ${label} (導入済み。更新はアプリ自身が行います)"
    return 0
  fi

  tmp="$(mktemp --suffix=.deb)"
  log "${label} の最新版をダウンロードします"
  if ! curl -fsSL --retry 3 --retry-delay 2 -o "$tmp" "$url"; then
    rm -f "$tmp"
    warn "${label} のダウンロードに失敗しました。スキップします。"
    return 0
  fi

  apt_update_once
  log "${label} を導入します"
  if ! apt-get "${APT_OPTS[@]}" install -y -qq "$tmp"; then
    rm -f "$tmp"
    warn "${label} の導入に失敗しました。"
    return 0
  fi
  rm -f "$tmp"
  log "導入: ${label}"
}

# install_pinned_deb <パッケージ名> <URL> <SHA256> <バージョン> <表示名>
install_pinned_deb() {
  local package="$1" url="$2" sha="$3" version="$4" label="$5" cached installed

  installed="$(dpkg-query -W -f='${Version}' "$package" 2>/dev/null || true)"
  if [ -n "$installed" ] && [ "${installed%%-*}" = "$version" ]; then
    log "変更なし: ${label} ${installed}"
    return 0
  fi

  cached="${CACHE_DIR}/$(basename "${url%%\?*}")"
  install -d "$CACHE_DIR"
  download_verify "$url" "$sha" "$cached"

  apt_update_once
  log "${label} ${version} を導入します"
  apt-get "${APT_OPTS[@]}" install -y -qq "$cached"
  log "導入: ${label} ${version}"
}

# 1Password は導入後、パッケージ自身が apt リポジトリ定義を管理する。
# こちらが毎回書き直すと、実行のたびに内容が入れ替わって冪等でなくなるため、
# 「まだ入っていないときだけ足場を作って導入する」方式にしている。
install_1password() {
  if package_installed "$ONEPASSWORD_PACKAGE"; then
    log "変更なし: 1Password (apt リポジトリはパッケージ自身が管理します)"
    return 0
  fi

  install -d -m 0755 /etc/apt/keyrings

  local tmp
  tmp="$(mktemp)"
  log "1Password の署名鍵を取得します (導入用の足場)"
  if ! curl -fsSL --retry 3 --retry-delay 2 -o "$tmp" "$ONEPASSWORD_KEY_URL"; then
    rm -f "$tmp"
    warn "1Password の署名鍵の取得に失敗しました。スキップします。"
    return 0
  fi
  if ! gpg --dearmor <"$tmp" >"${ONEPASSWORD_BOOTSTRAP_KEYRING}.tmp"; then
    rm -f "$tmp" "${ONEPASSWORD_BOOTSTRAP_KEYRING}.tmp"
    warn "1Password の署名鍵の変換に失敗しました。スキップします。"
    return 0
  fi
  install -m 0644 "${ONEPASSWORD_BOOTSTRAP_KEYRING}.tmp" "$ONEPASSWORD_BOOTSTRAP_KEYRING"
  rm -f "$tmp" "${ONEPASSWORD_BOOTSTRAP_KEYRING}.tmp"

  write_file "$ONEPASSWORD_SOURCES" 0644 <<EOF
Types: deb
URIs: ${ONEPASSWORD_REPO_URL}
Suites: stable
Components: main
Architectures: amd64
Signed-By: ${ONEPASSWORD_BOOTSTRAP_KEYRING}
EOF

  APT_UPDATED=0
  apt_update_once
  log "1Password を導入します"
  if ! apt-get "${APT_OPTS[@]}" install -y -qq "$ONEPASSWORD_PACKAGE"; then
    warn "1Password の導入に失敗しました。"
    return 0
  fi

  # 導入が済むと postinst が /usr/share/keyrings/ に自前の鍵を置き、
  # sources も自分の内容で書き換える。足場の鍵はもう使われないので片付ける。
  rm -f "$ONEPASSWORD_BOOTSTRAP_KEYRING"
  log "導入: 1Password (以後の更新はパッケージ自身の apt チャンネルが担当)"
}

main() {
  require_root

  local arch
  arch="$(deb_arch)"
  if [ "$arch" != "amd64" ]; then
    log "アーキテクチャが ${arch} のため、このモジュールはスキップします。"
    log "Discord / Zoom / 1Password / Dropbox は公式が amd64 版しか配布していません。"
    return 0
  fi

  install_latest_deb "$DISCORD_PACKAGE" "$DISCORD_URL" "Discord"
  install_latest_deb "$ZOOM_PACKAGE" "$ZOOM_URL" "Zoom"
  install_pinned_deb "$DROPBOX_PACKAGE" "$DROPBOX_URL" "$DROPBOX_SHA256" \
    "$DROPBOX_VERSION" "Dropbox"

  install_1password

  log "Dropbox は初回起動時に本体をダウンロードします (アプリから案内が出ます)。"
}

main "$@"
