#!/usr/bin/env bash
#
# 静的検証: リポジトリの構造と、モジュールが参照するファイルの実在確認。
# ゲストや VM がなくても Mac 上で実行できる。
#
#   ./tests/static-checks.sh
#
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILURES=0

pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
diag() { printf '#   %s\n' "$*"; }

check_exists() {
  local path="$1" desc="${2:-$1 が存在する}"
  if [ -e "${REPO_ROOT}/${path}" ]; then pass "$desc"; else fail "$desc"; fi
}

printf '=== 必須ファイルの実在 ===\n'
for p in install.sh README.md lib/common.sh bin/first-run-wizard \
  harness/vmtest harness/config.env.example \
  docs/development.md docs/vm-setup.md docs/vm-testing.md \
  files/skel/.zshrc files/skel/.zimrc \
  files/skel/.config/ghostty/config \
  files/skel/.config/xremap/config.yml \
  files/skel/.config/autostart/first-run-wizard.desktop \
  files/systemd/xremap.service \
  files/claude-skills/herdr-ops/SKILL.md \
  "files/gnome-extensions/xremap@k0kubun.com.v15.shell-extension.zip"; do
  check_exists "$p"
done

printf '\n=== モジュールの体裁 ===\n'
for m in "${REPO_ROOT}"/modules/*.sh; do
  name="$(basename "$m")"
  if grep -q 'set -euo pipefail' "$m"; then
    pass "${name} が set -euo pipefail を持つ"
  else
    fail "${name} が set -euo pipefail を持つ"
  fi
  if grep -q 'lib/common.sh' "$m"; then
    pass "${name} が lib/common.sh を読み込む"
  else
    fail "${name} が lib/common.sh を読み込む"
  fi
  if grep -q '^MODULE_NAME=' "$m"; then
    pass "${name} が MODULE_NAME を設定する"
  else
    fail "${name} が MODULE_NAME を設定する"
  fi
done

printf '\n=== モジュールが参照するリポジトリ内ファイル ===\n'
# ${REPO_ROOT}/... の形で参照されているパスがすべて存在することを確かめる
missing=0
while IFS= read -r ref; do
  rel="${ref#\$\{REPO_ROOT\}/}"
  if [ -e "${REPO_ROOT}/${rel}" ]; then
    continue
  fi
  diag "参照先がありません: ${rel}"
  missing=$((missing + 1))
done < <(grep -rhoE '\$\{REPO_ROOT\}/[A-Za-z0-9@._/-]+' "${REPO_ROOT}/modules" | sort -u)

if [ "$missing" -eq 0 ]; then
  pass "モジュールが参照するリポジトリ内ファイルがすべて存在する"
else
  fail "モジュールが参照するリポジトリ内ファイルがすべて存在する"
fi

printf '\n=== 配置先パスの妥当性 ===\n'
# install_file / write_file の配置先はすべて絶対パスでなければならない
bad=0
# grep のパターン。$ をシェルに展開させないため単一引用符で変数に入れておく。
# shellcheck disable=SC2016
dest_pattern='(install_file|write_file) [^ ]+ +"?(/[A-Za-z0-9@._/${}-]+)'
while IFS= read -r dest; do
  case "$dest" in
    /*) ;;
    *) diag "絶対パスではない配置先: ${dest}"; bad=$((bad + 1)) ;;
  esac
done < <(grep -rhoE "$dest_pattern" "${REPO_ROOT}/modules" |
  awk '{print $3}' | tr -d '"' | sort -u)

if [ "$bad" -eq 0 ]; then
  pass "install_file / write_file の配置先がすべて絶対パス"
else
  fail "install_file / write_file の配置先がすべて絶対パス"
fi

printf '\n=== 認証情報が含まれていないこと ===\n'
if grep -rIlE 'sk-ant-[A-Za-z0-9]|ghp_[A-Za-z0-9]{20}|github_pat_[A-Za-z0-9]{20}' \
  "$REPO_ROOT" --exclude-dir=.git >/dev/null 2>&1; then
  fail "リポジトリに API キーらしき文字列がない"
  grep -rIlE 'sk-ant-[A-Za-z0-9]|ghp_[A-Za-z0-9]{20}|github_pat_[A-Za-z0-9]{20}' \
    "$REPO_ROOT" --exclude-dir=.git | while IFS= read -r f; do diag "$f"; done
else
  pass "リポジトリに API キーらしき文字列がない"
fi

printf '\n=== 同梱バイナリのチェックサム ===\n'
EXT_ZIP="files/gnome-extensions/xremap@k0kubun.com.v15.shell-extension.zip"
EXT_SHA="9f81d40ecc23810c704f0e6e6d9cc69c25e7c5528c24576a4972056b5b7d6d5a"
if [ -f "${REPO_ROOT}/${EXT_ZIP}" ]; then
  actual="$(shasum -a 256 "${REPO_ROOT}/${EXT_ZIP}" 2>/dev/null | cut -d' ' -f1)"
  [ -n "$actual" ] || actual="$(sha256sum "${REPO_ROOT}/${EXT_ZIP}" | cut -d' ' -f1)"
  if [ "$actual" = "$EXT_SHA" ]; then
    pass "同梱の xremap GNOME 拡張のチェックサムが一致する"
  else
    fail "同梱の xremap GNOME 拡張のチェックサムが一致する"
    diag "期待 ${EXT_SHA} / 実際 ${actual}"
  fi
fi

printf '\n=== herdr スキルとモジュールのバージョン整合 ===\n'
herdr_version="$(grep -oE 'HERDR_VERSION="[0-9.]+"' "${REPO_ROOT}/modules/50-herdr.sh" |
  head -n 1 | tr -d '"' | cut -d= -f2)"
if [ -n "$herdr_version" ]; then
  pass "50-herdr.sh の HERDR_VERSION は ${herdr_version}"
  diag "同梱スキルは herdr v${herdr_version} の skills/herdr/SKILL.md から取得"
  diag "実機では 65-agent-tooling.sh が herdr --skill の出力を優先する"
else
  fail "50-herdr.sh から HERDR_VERSION を読み取れる"
fi

printf '\n失敗数: %d\n' "$FAILURES"
exit "$FAILURES"
