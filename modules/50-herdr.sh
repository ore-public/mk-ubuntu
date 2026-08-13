#!/usr/bin/env bash
#
# F5. herdr
#
# herdr は AI コーディングエージェント向けのターミナルマルチプレクサ。
# 公式インストーラ (https://herdr.dev/install.sh) は ~/.local/bin に入れるため、
# ここでは同じ配布物 (GitHub Releases のバイナリ) を直接取得して
# システムワイドの /usr/local/bin に置く。バージョンは固定する。
#
# Claude Code 統合 (herdr integration install claude) は認証後でないと意味がないため、
# first-run-wizard から実行する。
#
# ライセンス: herdr は AGPL-3.0 / 商用のデュアルライセンス。
# 本リポジトリの成果物を外部配布する場合は条件確認が必要 (README のライセンス節を参照)。
#
set -euo pipefail

MODULE_NAME="50-herdr"
# shellcheck source=lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

HERDR_VERSION="0.8.0"
HERDR_BASE_URL="https://github.com/herdrdev/herdr/releases/download/v${HERDR_VERSION}"
HERDR_ASSET_AMD64="herdr-linux-x86_64"
HERDR_SHA256_AMD64="b872ea7e40fa2cb17e857ac9b62b1bf26db7b403c622f5d2f3f5b35f6e9acd28"
HERDR_ASSET_ARM64="herdr-linux-aarch64"
HERDR_SHA256_ARM64="f647ac66468d9efbc642fe534fb284468f0aea60641606fc008dfc0d82a3ca87"

HERDR_BIN="/usr/local/bin/herdr"
HERDR_CACHE_DIR="/var/cache/mk-ubuntu"

main() {
  require_root

  if [ -x "$HERDR_BIN" ] &&
    "$HERDR_BIN" --version 2>/dev/null | grep -qF "$HERDR_VERSION"; then
    log "変更なし: ${HERDR_BIN} ($("$HERDR_BIN" --version 2>/dev/null))"
    return 0
  fi

  local asset sha cached
  asset="$(pick_arch "$HERDR_ASSET_AMD64" "$HERDR_ASSET_ARM64")"
  sha="$(pick_arch "$HERDR_SHA256_AMD64" "$HERDR_SHA256_ARM64")"
  cached="${HERDR_CACHE_DIR}/${asset}-${HERDR_VERSION}"

  install -d "$HERDR_CACHE_DIR"
  download_verify "${HERDR_BASE_URL}/${asset}" "$sha" "$cached"
  install -m 0755 "$cached" "$HERDR_BIN"

  log "配置: ${HERDR_BIN} ($("$HERDR_BIN" --version 2>/dev/null || echo 'バージョン取得失敗'))"
  log "Claude Code 統合とプラグイン導入は first-run-wizard が行います。"
}

main "$@"
