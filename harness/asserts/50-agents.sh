#!/usr/bin/env bash
# F5 / F6. herdr と AI エージェント各種の検証。
set -uo pipefail
# shellcheck source=harness/asserts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

HERDR_VERSION="0.8.0"
CLAUDE_CODE_VERSION="2.1.231"
COPILOT_CLI_VERSION="1.0.79"
OPENCODE_VERSION="1.18.18"

# herdr はユーザーローカルではなくシステムワイドに置く
check "herdr が /usr/local/bin にある" test -x /usr/local/bin/herdr
check_cmd_output "herdr のバージョンが ${HERDR_VERSION}" "$HERDR_VERSION" \
  /usr/local/bin/herdr --version

# Node.js は apt (universe) の nodejs 22 系
check_cmd_output "node のメジャーバージョンが 22 以上" "^v(2[2-9]|[3-9][0-9])\." node --version
check "npm がある" bash -c "command -v npm"

check_cmd_output "Claude Code のバージョンが ${CLAUDE_CODE_VERSION}" "$CLAUDE_CODE_VERSION" \
  claude --version
check_cmd_output "Copilot CLI のバージョンが ${COPILOT_CLI_VERSION}" "$COPILOT_CLI_VERSION" \
  copilot --version
check_cmd_output "opencode のバージョンが ${OPENCODE_VERSION}" "$OPENCODE_VERSION" \
  opencode --version
check "gh がある" bash -c "command -v gh"

# 初回ウィザード
check "first-run-wizard が実行可能" test -x /usr/local/bin/first-run-wizard
check_file /etc/skel/.config/autostart/first-run-wizard.desktop
check_contains /etc/skel/.config/autostart/first-run-wizard.desktop \
  "^Exec=ghostty .*-e /usr/local/bin/first-run-wizard$" \
  "自動起動 .desktop が Ghostty でウィザードを開く"
check_contains /etc/skel/.config/autostart/first-run-wizard.desktop \
  "^Exec=ghostty --title=" \
  "自動起動 .desktop がウィンドウタイトルを指定している"

# 認証情報が焼き込まれていないこと
check "リポジトリ由来の設定に API キーが含まれていない" \
  bash -c "! grep -rIl -E 'sk-ant-|ghp_|github_pat_' /etc/skel /usr/local/bin/first-run-wizard 2>/dev/null | grep -q ."

assert_exit
