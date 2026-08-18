#!/usr/bin/env bash
# Git ホスティングの CLI (gh / glab) の検証。
set -uo pipefail
# shellcheck source=harness/asserts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

GLAB_VERSION="1.114.0"

# --- gh (GitHub 公式 apt リポジトリ) ---
check "gh コマンドがある" bash -c "command -v gh"
check_file /etc/apt/keyrings/githubcli-archive-keyring.gpg
check_file /etc/apt/sources.list.d/github-cli.sources
check_contains /etc/apt/sources.list.d/github-cli.sources \
  "^URIs: https://cli\.github\.com/packages$" \
  "gh が GitHub 公式リポジトリを参照している"
check_contains /etc/apt/sources.list.d/github-cli.sources \
  "^Signed-By: /etc/apt/keyrings/githubcli-archive-keyring\.gpg$" \
  "gh の sources が Signed-By で keyring を参照している"

# Ubuntu の古い版 (26.04 は 2.46) ではなく公式版が入っていること。
# 公式リポジトリの版は 2.90 以上なので、メジャー 2 のマイナーで判定する。
check_cmd_output "gh が Ubuntu 版より新しい (2.90 以上)" \
  "gh version 2\.(9[0-9]|[1-9][0-9]{2})" \
  bash -c "gh --version | head -1"

# --- glab (GitLab Releases の deb) ---
check "glab コマンドがある" bash -c "command -v glab"
check "glab が導入済み" \
  bash -c "dpkg-query -W -f='\${Status}' glab 2>/dev/null | grep -q '^install ok installed$'"
check_cmd_output "glab のバージョンが ${GLAB_VERSION}" "$GLAB_VERSION" \
  bash -c "glab --version"

# Ubuntu の universe 版 (1.53) を掴んでいないこと
check "glab が apt の universe 版ではない" \
  bash -c "! dpkg-query -W -f='\${Version}' glab 2>/dev/null | grep -q '^1\.53'"

# 実際に動くこと (サブコマンドのヘルプが出る)
check "gh auth のヘルプが出る" bash -c "gh auth --help >/dev/null 2>&1"
check "glab auth のヘルプが出る" bash -c "glab auth --help >/dev/null 2>&1"

assert_exit
