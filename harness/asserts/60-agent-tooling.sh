#!/usr/bin/env bash
# F6.5. Playwright MCP / Playwright ブラウザ / herdr スキルの検証。
set -uo pipefail
# shellcheck source=harness/asserts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PLAYWRIGHT_MCP_VERSION="0.0.79"
BROWSERS_DIR="/opt/playwright-browsers"

NPM_ROOT="$(npm root -g 2>/dev/null || echo /usr/local/lib/node_modules)"

check_file "${NPM_ROOT}/@playwright/mcp/package.json"
check_cmd_output "@playwright/mcp のバージョンが ${PLAYWRIGHT_MCP_VERSION}" \
  "\"version\": *\"${PLAYWRIGHT_MCP_VERSION}\"" \
  cat "${NPM_ROOT}/@playwright/mcp/package.json"
check "playwright-mcp コマンドが PATH にある" bash -c "command -v playwright-mcp"

# ブラウザはユーザーごとではなくシステム共有パスに事前配置する
check_dir "$BROWSERS_DIR"
check "共有パスに Chromium が配置されている" \
  bash -c "find ${BROWSERS_DIR} -maxdepth 1 -name 'chromium-*' -type d | grep -q ."
check "一般ユーザーが共有ブラウザを読める" \
  bash -c "find ${BROWSERS_DIR} -maxdepth 1 -name 'chromium-*' -type d -readable | grep -q ."
check_contains /etc/environment "^PLAYWRIGHT_BROWSERS_PATH=\"${BROWSERS_DIR}\"$" \
  "/etc/environment に PLAYWRIGHT_BROWSERS_PATH がある"
check "PLAYWRIGHT_BROWSERS_PATH の行が 1 行だけ" \
  bash -c "[ \"\$(grep -c '^PLAYWRIGHT_BROWSERS_PATH=' /etc/environment)\" -eq 1 ]"
check_file /etc/profile.d/mk-ubuntu-playwright.sh

# herdr 操作用の Claude Code スキル
check_file /etc/skel/.claude/skills/herdr-ops/SKILL.md
check_contains /etc/skel/.claude/skills/herdr-ops/SKILL.md "^description:" \
  "スキルに description の frontmatter がある"
check "スキルの name はディレクトリ名 (herdr-ops) に任せている" \
  bash -c "! grep -q '^name:' /etc/skel/.claude/skills/herdr-ops/SKILL.md"
check_contains /etc/skel/.claude/skills/herdr-ops/SKILL.md "HERDR_ENV" \
  "スキルが HERDR_ENV の確認手順を含む"

# スキルの内容は導入した herdr のバージョンから生成されている
if command -v herdr >/dev/null 2>&1 && herdr --skill >/tmp/herdr-skill.$$ 2>/dev/null; then
  check "スキル本文が herdr --skill の出力と一致する" \
    bash -c "diff <(sed '/^name:/d' /tmp/herdr-skill.$$) /etc/skel/.claude/skills/herdr-ops/SKILL.md"
  rm -f "/tmp/herdr-skill.$$"
else
  diag "herdr --skill が使えないため、スキル本文の一致確認はスキップしました。"
fi

assert_exit
