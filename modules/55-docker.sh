#!/usr/bin/env bash
#
# Docker Engine (Docker 公式の apt リポジトリ)
#
# Ubuntu の docker.io ではなく Docker 公式のパッケージを使う。
# 公式リポジトリは amd64 / arm64 の両方を配布しているのでアーキ分岐は要らない。
#
# 導入するもの:
#   docker-ce / docker-ce-cli / containerd.io
#   docker-buildx-plugin / docker-compose-plugin (docker compose コマンド)
#
# sudo なしで docker を使えるよう docker グループを既定に追加する。
# **docker グループはホストの root 権限と同等**なので、その点は
# README とログで明示する。
#
set -euo pipefail

MODULE_NAME="55-docker"
# shellcheck source=lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

DOCKER_KEY_URL="https://download.docker.com/linux/ubuntu/gpg"
DOCKER_KEYRING="/etc/apt/keyrings/docker.gpg"
DOCKER_REPO_URL="https://download.docker.com/linux/ubuntu"
DOCKER_SOURCES="/etc/apt/sources.list.d/docker.sources"

DOCKER_PACKAGES=(
  docker-ce
  docker-ce-cli
  containerd.io
  docker-buildx-plugin
  docker-compose-plugin
)

# リポジトリの suite は Ubuntu のコードネーム (26.04 なら resolute)
docker_suite() {
  local codename=""
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    codename="$(. /etc/os-release && printf '%s' "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}")"
  fi
  [ -n "$codename" ] || die "Ubuntu のコードネームを判定できません。"

  # Docker 側にまだそのコードネームが無い場合に備えて存在を確かめる
  if curl -fsI --retry 2 -o /dev/null \
    "${DOCKER_REPO_URL}/dists/${codename}/Release" 2>/dev/null; then
    printf '%s' "$codename"
    return 0
  fi

  warn "Docker のリポジトリに ${codename} がまだありません。"
  die "対応コードネームが公開されるまで、このモジュールは適用できません。"
}

setup_repository() {
  install -d -m 0755 /etc/apt/keyrings

  if [ -f "$DOCKER_KEYRING" ]; then
    log "変更なし: $DOCKER_KEYRING"
  else
    local tmp
    tmp="$(mktemp)"
    log "Docker の署名鍵を取得します"
    curl -fsSL --retry 3 --retry-delay 2 -o "$tmp" "$DOCKER_KEY_URL" ||
      { rm -f "$tmp"; die "Docker の署名鍵の取得に失敗しました。"; }
    gpg --dearmor <"$tmp" >"${DOCKER_KEYRING}.tmp" ||
      { rm -f "$tmp" "${DOCKER_KEYRING}.tmp"; die "Docker の署名鍵の変換に失敗しました。"; }
    install -m 0644 "${DOCKER_KEYRING}.tmp" "$DOCKER_KEYRING"
    rm -f "$tmp" "${DOCKER_KEYRING}.tmp"
    log "配置: $DOCKER_KEYRING"
  fi

  local suite before=""
  suite="$(docker_suite)"
  [ -f "$DOCKER_SOURCES" ] && before="$(sha256sum "$DOCKER_SOURCES" | cut -d' ' -f1)"

  write_file "$DOCKER_SOURCES" 0644 <<EOF
Types: deb
URIs: ${DOCKER_REPO_URL}
Suites: ${suite}
Components: stable
Architectures: amd64 arm64
Signed-By: ${DOCKER_KEYRING}
EOF

  if [ "$before" != "$(sha256sum "$DOCKER_SOURCES" | cut -d' ' -f1)" ]; then
    APT_UPDATED=0
  fi
}

enable_service() {
  systemctl enable --now docker.service >/dev/null 2>&1 ||
    warn "docker.service の有効化に失敗しました。"
  systemctl enable --now containerd.service >/dev/null 2>&1 || true

  if systemctl is-active docker.service >/dev/null 2>&1; then
    log "docker.service は稼働中です"
  else
    warn "docker.service が稼働していません。"
  fi
}

main() {
  require_root

  setup_repository
  apt_install "${DOCKER_PACKAGES[@]}"
  enable_service

  # 新規ユーザーを既定で docker グループに入れる
  # (既存ユーザーへの付与は 70-existing-users.sh が行う)
  add_extra_group docker

  log "Docker: $(docker --version 2>/dev/null || echo '取得失敗')"
  log "Compose: $(docker compose version 2>/dev/null || echo '取得失敗')"
  log "注意: docker グループに入ると sudo なしでコンテナを起動できますが、"
  log "      これはホストの root 権限と同等の権限を持つことを意味します。"
  log "反映には再ログインが必要です。"
}

main "$@"
