#!/usr/bin/env bash
# F1.5. Brave と既定ブラウザの検証。
set -uo pipefail
# shellcheck source=harness/asserts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

check "brave-browser が導入済み" \
  bash -c "dpkg-query -W -f='\${Status}' brave-browser 2>/dev/null | grep -q '^install ok installed$'"
check_cmd_output "brave-browser がバージョンを返す" "[0-9]+\.[0-9]+" brave-browser --version

# keyring 方式 (apt-key は 26.04 に存在しない)
check_file /etc/apt/keyrings/brave-browser-archive-keyring.gpg
check_file /etc/apt/sources.list.d/brave-browser-release.sources
check_contains /etc/apt/sources.list.d/brave-browser-release.sources \
  "^Signed-By: /etc/apt/keyrings/brave-browser-archive-keyring.gpg$" \
  "Brave の sources が Signed-By で keyring を参照している"
check "apt-key が存在しない (26.04 で削除済み)" bash -c "! command -v apt-key"

# 既定ブラウザ (システムレベル)
check_contains /etc/xdg/mimeapps.list "^x-scheme-handler/https=brave-browser\.desktop$" \
  "/etc/xdg/mimeapps.list が https を Brave に向けている"
check_contains /etc/xdg/mimeapps.list "^text/html=brave-browser\.desktop$" \
  "/etc/xdg/mimeapps.list が text/html を Brave に向けている"
check_file /usr/share/applications/brave-browser.desktop

# Firefox は削除しない方針
check "Firefox が残っている" \
  bash -c "command -v firefox >/dev/null || snap list firefox >/dev/null 2>&1 || dpkg-query -W firefox >/dev/null 2>&1"

assert_exit
