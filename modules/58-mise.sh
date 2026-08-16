#!/usr/bin/env bash
#
# mise (プロジェクトごとの言語バージョン管理)
#
# Ruby / Node.js / PHP などを 1 つのツールで切り替える。
# rbenv や nodenv を言語ごとに入れる代わりに mise 1 つで済ませる。
#
# 本体はシステム共有の /usr/local/bin/mise に置き、
# 導入した言語のバージョンはユーザーごと (~/.local/share/mise) に持つ。
# 有効化は /etc/skel の .zshrc に入れた `mise activate` が行う。
#
# あわせて Ruby / PHP / Node.js のビルドに必要な apt パッケージを導入する。
# 言語ごとに事情が違う:
#   Ruby … ビルド済みバイナリがあればそれを使い、無ければ ruby-build で
#          ソースからビルドする。ビルド済みでも、ネイティブ拡張を持つ
#          gem のコンパイルにヘッダが要る。
#   PHP  … mise の PHP は必ずソースからビルドする (vfox-php プラグイン)。
#          依存はプラグインの systemDependencies の宣言に合わせている。
#   Node … 公式のビルド済みバイナリを使うので通常はビルドしない。
#          ソースからビルドしたい場合のために最小限だけ入れる。
#
# 注意: AI エージェント (claude / copilot など) はシステムの Node.js で
# 動かしている。mise でプロジェクトに古い Node.js を指定すると、
# そのディレクトリではエージェントが動かなくなることがある。
# 詳しくは docs/development.md の設計判断を参照。
#
set -euo pipefail

MODULE_NAME="58-mise"
# shellcheck source=lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

MISE_VERSION="v2026.8.6"
MISE_BASE_URL="https://github.com/jdx/mise/releases/download/${MISE_VERSION}"
MISE_ASSET_AMD64="mise-${MISE_VERSION}-linux-x64.tar.gz"
MISE_SHA256_AMD64="cfe49784ec9683b38510846958cfecd9b59da84d4e8a38d18ffda19dc2941ead"
MISE_ASSET_ARM64="mise-${MISE_VERSION}-linux-arm64.tar.gz"
MISE_SHA256_ARM64="b92744ceb9a01f0bb198bfcf2ba49c36918c9e4353a34be50f23d5b6e93c28ee"

MISE_BIN="/usr/local/bin/mise"
CACHE_DIR="/var/cache/mk-ubuntu"

# Ruby のビルドと、ネイティブ拡張を持つ gem のコンパイルに必要なもの。
# ruby-build の「Suggested build environment」を Ubuntu 26.04 で
# 実在するパッケージ名に直したもの
# (libreadline6-dev / libncurses5-dev / libgdbm6 は 26.04 にはない)。
RUBY_BUILD_DEPS=(
  autoconf
  patch
  build-essential
  rustc
  libssl-dev
  libyaml-dev
  libreadline-dev
  zlib1g-dev
  libgmp-dev
  libncurses-dev
  libffi-dev
  libgdbm-dev
  libdb-dev
  uuid-dev
  pkg-config
)

# PHP をソースからビルドするのに必要なもの。
# mise の PHP プラグイン (vfox-php) の systemDependencies が挙げている
# apt パッケージ名を、26.04 で実在する名前に直したもの
# (libfreetype6-dev は 26.04 には無く libfreetype-dev が正)。
# build-essential / autoconf / pkg-config / libssl-dev / zlib1g-dev /
# libgmp-dev / libreadline-dev は Ruby 側と重複するのでここには書かない。
PHP_BUILD_DEPS=(
  bison
  re2c
  libxml2-dev
  libonig-dev
  libicu-dev
  libzip-dev
  libcurl4-openssl-dev
  libsqlite3-dev
  libpng-dev
  # libpng があると configure が --with-external-gd を有効にし、
  # その時点で gdlib.pc を要求する。libgd-dev がないとビルドが止まる
  # (プラグインの systemDependencies には挙がっていない。実機で判明)
  libgd-dev
  libfreetype-dev
  libjpeg-dev
  libwebp-dev
  libsodium-dev
)

# Node.js は公式のビルド済みバイナリが使われるので通常はビルドしない。
# ソースからビルドする場合と、ネイティブモジュール (node-gyp) の
# コンパイルに必要なものだけ入れておく。
NODE_BUILD_DEPS=(
  python3
  g++
  make
)

install_mise() {
  if [ -x "$MISE_BIN" ] &&
    "$MISE_BIN" --version 2>/dev/null | grep -qF "${MISE_VERSION#v}"; then
    log "変更なし: ${MISE_BIN} ($("$MISE_BIN" --version 2>/dev/null))"
    return 0
  fi

  local asset sha cached extract_dir
  asset="$(pick_arch "$MISE_ASSET_AMD64" "$MISE_ASSET_ARM64")"
  sha="$(pick_arch "$MISE_SHA256_AMD64" "$MISE_SHA256_ARM64")"
  cached="${CACHE_DIR}/${asset}"

  install -d "$CACHE_DIR"
  download_verify "${MISE_BASE_URL}/${asset}" "$sha" "$cached"

  extract_dir="$(mktemp -d)"
  tar -xzf "$cached" -C "$extract_dir"
  [ -f "${extract_dir}/mise/bin/mise" ] ||
    { rm -rf "$extract_dir"; die "tar に mise/bin/mise が入っていません。"; }
  install -m 0755 "${extract_dir}/mise/bin/mise" "$MISE_BIN"
  rm -rf "$extract_dir"

  log "配置: ${MISE_BIN} ($("$MISE_BIN" --version 2>/dev/null || echo 'バージョン取得失敗'))"
}

main() {
  require_root

  install_mise
  apt_install "${RUBY_BUILD_DEPS[@]}" "${PHP_BUILD_DEPS[@]}" "${NODE_BUILD_DEPS[@]}"

  log "mise ${MISE_VERSION} を導入しました。"
  log "Ruby / PHP / Node.js のビルド依存を導入済みです。"
  log "使い方の例:"
  log "  mise use -g ruby@3.4      # 全体で使う Ruby を決める"
  log "  mise use ruby@3.4         # そのディレクトリだけ (mise.toml が作られる)"
  log "  mise use node@22 php@8.4  # 他の言語も同じ書き方"
  log "PHP はソースからビルドするため、初回は時間がかかります。"
  log "シェルでの有効化は /etc/skel の .zshrc に入っています (再ログインで有効)。"
}

main "$@"
