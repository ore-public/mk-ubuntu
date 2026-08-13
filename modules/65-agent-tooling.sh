#!/usr/bin/env bash
#
# F6.5. エージェント連携ツーリング (システム側で置けるもの)
#
# - Playwright MCP をバージョン固定でグローバル導入する
# - Playwright のブラウザ (Chromium のみ) をシステム共有パスに事前配置し、
#   PLAYWRIGHT_BROWSERS_PATH をシステム環境変数にする
# - herdr 操作用の Claude Code スキルを /etc/skel/.claude/skills/herdr-ops/ に置く
#
# Claude Code への MCP 登録 (ユーザースコープ) と herdr-reviewr の導入は
# ユーザー単位なので first-run-wizard が行う。
#
set -euo pipefail

MODULE_NAME="65-agent-tooling"
# shellcheck source=lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

PLAYWRIGHT_MCP_VERSION="0.0.79"
PLAYWRIGHT_BROWSERS_DIR="/opt/playwright-browsers"
PROFILE_D_FILE="/etc/profile.d/mk-ubuntu-playwright.sh"

SKEL_SKILLS_DIR="/etc/skel/.claude/skills"
HERDR_SKILL_DIR="${SKEL_SKILLS_DIR}/herdr-ops"
HERDR_SKILL_VENDORED="${REPO_ROOT}/files/claude-skills/herdr-ops/SKILL.md"

npm_global_version() {
  local pkg="$1" root
  root="$(npm root -g 2>/dev/null)" || return 0
  [ -f "${root}/${pkg}/package.json" ] || return 0
  python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['version'])" \
    "${root}/${pkg}/package.json" 2>/dev/null || true
}

install_playwright_mcp() {
  local current
  current="$(npm_global_version "@playwright/mcp")"
  if [ "$current" = "$PLAYWRIGHT_MCP_VERSION" ]; then
    log "変更なし: @playwright/mcp@${PLAYWRIGHT_MCP_VERSION}"
    return 0
  fi
  log "npm install -g @playwright/mcp@${PLAYWRIGHT_MCP_VERSION}"
  npm install -g --no-fund --no-audit "@playwright/mcp@${PLAYWRIGHT_MCP_VERSION}"
}

# ブラウザは全ユーザー共有の 1 か所に置く。
# ユーザーごとに ~/.cache/ms-playwright へダウンロードさせない
# (Chromium だけでも 1 ユーザーあたり数百 MB 消費するため)。
set_browsers_path_env() {
  # PAM (pam_env) 経由でグラフィカルセッションにも効く
  if [ -f /etc/environment ]; then
    set_conf_key /etc/environment PLAYWRIGHT_BROWSERS_PATH "\"${PLAYWRIGHT_BROWSERS_DIR}\""
  else
    write_file /etc/environment 0644 <<EOF
PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_DIR}"
EOF
  fi

  # ログインシェル (bash / zsh どちらも /etc/profile を読む) 用
  write_file "$PROFILE_D_FILE" 0644 <<EOF
# Playwright のブラウザをユーザーごとに落とさず、システム共有の 1 か所を使う
export PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_DIR}"
EOF
}

install_browsers() {
  local pw_cli root
  root="$(npm root -g)"
  pw_cli="${root}/@playwright/mcp/node_modules/.bin/playwright"

  if [ ! -x "$pw_cli" ]; then
    warn "@playwright/mcp に同梱の playwright CLI が見つかりません: ${pw_cli}"
    warn "ブラウザの事前配置をスキップします。"
    return 0
  fi

  install -d "$PLAYWRIGHT_BROWSERS_DIR"

  if find "$PLAYWRIGHT_BROWSERS_DIR" -maxdepth 1 -name 'chromium-*' -type d |
    grep -q .; then
    log "変更なし: ${PLAYWRIGHT_BROWSERS_DIR} に Chromium が配置済み"
  else
    log "Chromium と依存ライブラリを ${PLAYWRIGHT_BROWSERS_DIR} に導入します"
    PLAYWRIGHT_BROWSERS_PATH="$PLAYWRIGHT_BROWSERS_DIR" \
      "$pw_cli" install --with-deps chromium ||
      die "playwright install --with-deps chromium に失敗しました。"
  fi

  # 全ユーザーから読めるようにする
  chmod -R a+rX "$PLAYWRIGHT_BROWSERS_DIR"
  log "ブラウザ配置サイズ: $(du -sh "$PLAYWRIGHT_BROWSERS_DIR" 2>/dev/null | cut -f1)"
}

# herdr 操作用スキル。
# herdr は MCP サーバーを持たないため Claude Code スキルとして提供する。
# 内容は herdr 公式が配布しているものを正とし、導入済みバイナリから取り出す
# (`herdr --skill`)。これにより 50-herdr.sh で固定したバージョンと必ず一致する。
# バイナリから取れない場合は、同じバージョンからリポジトリに同梱した写しを使う。
install_herdr_skill() {
  local src tmp
  tmp="$(mktemp)"

  if command -v herdr >/dev/null 2>&1 && herdr --skill >"$tmp" 2>/dev/null && [ -s "$tmp" ]; then
    log "herdr --skill の出力からスキルを生成します"
    src="$tmp"
  else
    log "リポジトリ同梱の写しからスキルを生成します"
    src="$HERDR_SKILL_VENDORED"
  fi

  # Claude Code はスキル名をディレクトリ名から決める。
  # 公式の frontmatter は name: herdr だが、配置先は herdr-ops なので
  # name 行を落としてディレクトリ名 (herdr-ops) を採用させる。
  python3 - "$src" <<'PY' | write_file "${HERDR_SKILL_DIR}/SKILL.md" 0644
import sys

lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
out, in_front, seen_front = [], False, False
for line in lines:
    if line.strip() == "---" and not seen_front:
        in_front = True
        seen_front = True
        out.append(line)
        continue
    if in_front and line.strip() == "---":
        in_front = False
        out.append(line)
        continue
    if in_front and line.startswith("name:"):
        continue
    out.append(line)
sys.stdout.write("\n".join(out))
PY

  rm -f "$tmp"
  chmod -R a+rX "$SKEL_SKILLS_DIR"
}

main() {
  require_root

  command -v npm >/dev/null 2>&1 ||
    die "npm が見つかりません。先に 60-agents.sh を実行してください。"

  install_playwright_mcp
  set_browsers_path_env
  install_browsers
  install_herdr_skill

  log "Playwright MCP のバージョン: ${PLAYWRIGHT_MCP_VERSION}"
  log "Claude Code への MCP 登録と herdr-reviewr の導入は first-run-wizard が行います。"
}

main "$@"
