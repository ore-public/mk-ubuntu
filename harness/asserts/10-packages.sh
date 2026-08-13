#!/usr/bin/env bash
# F1. パッケージ基盤の検証。
set -uo pipefail
# shellcheck source=harness/asserts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PACKAGES=(
  zsh fzf bat curl git build-essential ghostty
  gnome-shell-extensions gnome-browser-connector
  ripgrep unzip dconf-cli xdg-terminal-exec jq
)

for pkg in "${PACKAGES[@]}"; do
  check "apt パッケージが導入済み: ${pkg}" \
    bash -c "dpkg-query -W -f='\${Status}' '${pkg}' 2>/dev/null | grep -q '^install ok installed$'"
done

check "batcat が存在する" test -x /usr/bin/batcat
check "bat が batcat への系統リンクである" \
  bash -c "[ \"\$(readlink -f /usr/local/bin/bat)\" = /usr/bin/batcat ]"

check_cmd_output "ghostty が起動しバージョンを返す" "[0-9]+\.[0-9]+" ghostty --version
check_cmd_output "fzf が起動しバージョンを返す" "[0-9]+\.[0-9]+" fzf --version

# Ptyxis はアンインストールしない方針
check "Ptyxis が残っている" \
  bash -c "dpkg-query -W -f='\${Status}' ptyxis 2>/dev/null | grep -q '^install ok installed$'"

assert_exit
