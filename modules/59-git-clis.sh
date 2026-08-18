#!/usr/bin/env bash
#
# Git ホスティングの CLI (gh / glab)
#
# どちらも Ubuntu の universe にあるが、上流から大きく遅れている
# (26.04 時点で gh 2.46 / glab 1.53 に対し、上流は gh 2.97 / glab 1.114)。
# 日々使うツールで機能差が大きいため、ベンダー公式の配布物を使う。
#
#   gh   … GitHub 公式の apt リポジトリ。更新が apt で届く
#   glab … GitLab の Releases にある deb。apt リポジトリが無いので
#          バージョン固定 + SHA256 検証で入れる
#
set -euo pipefail

MODULE_NAME="59-git-clis"
# shellcheck source=lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

CACHE_DIR="/var/cache/mk-ubuntu"

# gh: GitHub 公式 apt リポジトリ
GH_KEY_URL="https://cli.github.com/packages/githubcli-archive-keyring.gpg"
GH_KEYRING="/etc/apt/keyrings/githubcli-archive-keyring.gpg"
GH_REPO_URL="https://cli.github.com/packages"
GH_SOURCES="/etc/apt/sources.list.d/github-cli.sources"

# glab: GitLab Releases の deb (apt リポジトリが無い)
GLAB_VERSION="1.114.0"
GLAB_BASE_URL="https://gitlab.com/api/v4/projects/gitlab-org%2Fcli/packages/generic/glab/1%2E114%2E0"
GLAB_ASSET_AMD64="glab_1%2E114%2E0_linux_amd64%2Edeb"
GLAB_SHA256_AMD64="6df680f88a2a45700d1dd6a08a44a74838473ef3dcc5cb1ad243f4d1fd704ad0"
GLAB_ASSET_ARM64="glab_1%2E114%2E0_linux_arm64%2Edeb"
GLAB_SHA256_ARM64="c2bcb44cc10d849cccb879e687f3b9e102a3415c3d02f0cecfd9ce1442519350"

# apt_install は「導入済みなら何もしない」ので、universe の古い版が
# 既に入っている環境では公式リポジトリを足しても古いままになる。
# 候補版と食い違っていたら明示的に入れ直す。
apt_install_or_upgrade() {
  local package="$1" installed candidate
  installed="$(dpkg-query -W -f='${Version}' "$package" 2>/dev/null || true)"
  candidate="$(apt-cache policy "$package" 2>/dev/null | awk '/Candidate:/ {print $2}')"

  if [ -z "$candidate" ] || [ "$candidate" = "(none)" ]; then
    die "${package} の候補が見つかりません。apt の設定を確認してください。"
  fi

  if [ "$installed" = "$candidate" ]; then
    log "変更なし: ${package} ${installed}"
    return 0
  fi

  if [ -n "$installed" ]; then
    log "${package} を ${installed} から ${candidate} に更新します"
  else
    log "${package} ${candidate} を導入します"
  fi
  apt-get "${APT_OPTS[@]}" install -y -qq "$package"
}

setup_gh_repository() {
  install -d -m 0755 /etc/apt/keyrings

  if [ -f "$GH_KEYRING" ]; then
    log "変更なし: $GH_KEYRING"
  else
    local tmp
    tmp="$(mktemp)"
    log "GitHub CLI の署名鍵を取得します"
    if ! curl -fsSL --retry 3 --retry-delay 2 -o "$tmp" "$GH_KEY_URL"; then
      rm -f "$tmp"
      die "GitHub CLI の署名鍵の取得に失敗しました。"
    fi
    # 配布されているのは既にバイナリ形式なので dearmor は不要
    install -m 0644 "$tmp" "$GH_KEYRING"
    rm -f "$tmp"
    log "配置: $GH_KEYRING"
  fi

  local before=""
  [ -f "$GH_SOURCES" ] && before="$(sha256sum "$GH_SOURCES" | cut -d' ' -f1)"

  write_file "$GH_SOURCES" 0644 <<EOF
Types: deb
URIs: ${GH_REPO_URL}
Suites: stable
Components: main
Architectures: amd64 arm64
Signed-By: ${GH_KEYRING}
EOF

  if [ "$before" != "$(sha256sum "$GH_SOURCES" | cut -d' ' -f1)" ]; then
    APT_UPDATED=0
  fi
}

install_glab() {
  local installed
  installed="$(dpkg-query -W -f='${Version}' glab 2>/dev/null || true)"
  if [ "${installed%%-*}" = "$GLAB_VERSION" ]; then
    log "変更なし: glab ${installed}"
    return 0
  fi

  local asset sha cached
  asset="$(pick_arch "$GLAB_ASSET_AMD64" "$GLAB_ASSET_ARM64")"
  sha="$(pick_arch "$GLAB_SHA256_AMD64" "$GLAB_SHA256_ARM64")"
  cached="${CACHE_DIR}/glab_${GLAB_VERSION}_$(deb_arch).deb"

  install -d "$CACHE_DIR"
  download_verify "${GLAB_BASE_URL}/${asset}" "$sha" "$cached"

  apt_update_once
  log "glab ${GLAB_VERSION} を導入します"
  apt-get "${APT_OPTS[@]}" install -y -qq "$cached"
  log "導入: glab ${GLAB_VERSION}"
}

main() {
  require_root

  setup_gh_repository
  # リポジトリを足した直後は候補が変わるので、必ず読み直してから判断する
  apt_update_once
  apt_install_or_upgrade gh
  install_glab

  log "gh  : $(gh --version 2>/dev/null | head -n 1 || echo '取得失敗')"
  log "glab: $(glab --version 2>/dev/null | head -n 1 || echo '取得失敗')"
  log "認証は各自で行ってください: gh auth login / glab auth login"
}

main "$@"
