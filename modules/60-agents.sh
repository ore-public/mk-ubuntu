#!/usr/bin/env bash
#
# F6. AI エージェント + 初回ウィザード (システム側の準備)
#
# - Node.js LTS をシステムワイドに導入する
#   Ubuntu 26.04 の universe に nodejs 22.22 系があり、
#   Claude Code の要求 (node >= 22) を満たすので NodeSource は使わない。
# - Claude Code / GitHub Copilot CLI を npm でグローバル導入する (バージョン固定)
# - opencode を GitHub Releases のバイナリで導入する (バージョン固定 + SHA256 検証)
# - first-run-wizard 本体と、その自動起動 .desktop を配置する
#
# API キー・認証情報は一切ここで扱わない。認証は first-run-wizard が対話的に行う。
#
set -euo pipefail

MODULE_NAME="60-agents"
# shellcheck source=lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

CLAUDE_CODE_VERSION="2.1.231"
COPILOT_CLI_VERSION="1.0.79"

OPENCODE_VERSION="1.18.18"
OPENCODE_BASE_URL="https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}"
# baseline 版ではなく通常版を使う (新しめの CPU 命令を使う方)。
# 古い x86_64 CPU で起動しない場合は baseline 版に差し替える。
OPENCODE_ASSET_AMD64="opencode-linux-x64.tar.gz"
OPENCODE_SHA256_AMD64="0cddc222418b8553669905a8980c0cda7088f00da24d83d6ac76b01c9fdb2aaf"
OPENCODE_ASSET_ARM64="opencode-linux-arm64.tar.gz"
OPENCODE_SHA256_ARM64="dcb1b5ec5687b43f87749560021f9203f3809e0ce5ae44ff9be8ae17083fe4ba"
OPENCODE_BIN="/usr/local/bin/opencode"

CACHE_DIR="/var/cache/mk-ubuntu"

# npm のグローバル導入先にある指定パッケージのバージョンを出力する
npm_global_version() {
  local pkg="$1" root
  root="$(npm root -g 2>/dev/null)" || return 0
  [ -f "${root}/${pkg}/package.json" ] || return 0
  python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['version'])" \
    "${root}/${pkg}/package.json" 2>/dev/null || true
}

npm_install_pinned() {
  local pkg="$1" version="$2" current
  current="$(npm_global_version "$pkg")"
  if [ "$current" = "$version" ]; then
    log "変更なし: ${pkg}@${version}"
    return 0
  fi
  log "npm install -g ${pkg}@${version}"
  npm install -g --no-fund --no-audit "${pkg}@${version}"
}

install_node() {
  apt_install nodejs npm
  log "node: $(node --version 2>/dev/null || echo '取得失敗') / npm: $(npm --version 2>/dev/null || echo '取得失敗')"

  local node_major
  node_major="$(node --version 2>/dev/null | sed 's/^v//; s/\..*//')"
  if [ -n "$node_major" ] && [ "$node_major" -lt 22 ]; then
    die "Claude Code は Node.js 22 以上を要求します (検出: v${node_major})。"
  fi
}

install_opencode() {
  if [ -x "$OPENCODE_BIN" ] &&
    "$OPENCODE_BIN" --version 2>/dev/null | grep -qF "$OPENCODE_VERSION"; then
    log "変更なし: ${OPENCODE_BIN} ($("$OPENCODE_BIN" --version 2>/dev/null))"
    return 0
  fi

  local asset sha cached extract_dir
  asset="$(pick_arch "$OPENCODE_ASSET_AMD64" "$OPENCODE_ASSET_ARM64")"
  sha="$(pick_arch "$OPENCODE_SHA256_AMD64" "$OPENCODE_SHA256_ARM64")"
  cached="${CACHE_DIR}/opencode-${OPENCODE_VERSION}-${asset}"

  install -d "$CACHE_DIR"
  download_verify "${OPENCODE_BASE_URL}/${asset}" "$sha" "$cached"

  extract_dir="$(mktemp -d)"
  tar -xzf "$cached" -C "$extract_dir"
  [ -f "${extract_dir}/opencode" ] || { rm -rf "$extract_dir"; die "tar に opencode が入っていません。"; }
  install -m 0755 "${extract_dir}/opencode" "$OPENCODE_BIN"
  rm -rf "$extract_dir"
  log "配置: ${OPENCODE_BIN} ($("$OPENCODE_BIN" --version 2>/dev/null || echo 'バージョン取得失敗'))"
}

install_wizard() {
  install_file "${REPO_ROOT}/bin/first-run-wizard" /usr/local/bin/first-run-wizard 0755
  install_file "${REPO_ROOT}/files/skel/.config/autostart/first-run-wizard.desktop" \
    /etc/skel/.config/autostart/first-run-wizard.desktop 0644
}

main() {
  require_root

  install_node
  npm_install_pinned "@anthropic-ai/claude-code" "$CLAUDE_CODE_VERSION"
  npm_install_pinned "@github/copilot" "$COPILOT_CLI_VERSION"
  install_opencode
  # gh は 59-git-clis.sh が GitHub 公式リポジトリから導入する
  # (Copilot CLI の認証 gh auth login で使う)
  install_wizard

  log "導入したエージェント:"
  log "  claude  : $(claude --version 2>/dev/null || echo '取得失敗')"
  log "  copilot : $(copilot --version 2>/dev/null || echo '取得失敗')"
  log "  opencode: $(opencode --version 2>/dev/null || echo '取得失敗')"
  log "認証は初回ログイン時の first-run-wizard で行います。"
}

main "$@"
