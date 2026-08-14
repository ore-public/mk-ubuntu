#!/usr/bin/env bash
# 管理ファイルと個人ファイルの扱いを検証する。
#
#   管理ファイル … install.sh のたびに上書きされる (更新が行き渡る)
#   個人ファイル … 無いときだけ作られ、以後は触られない
#
# 実際にホームのファイルを書き換えてから install.sh を流し、
# 期待どおり戻る / 残ることを確かめる。
set -uo pipefail
# shellcheck source=harness/asserts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

REPO_DIR="${HOME}/distro-setup"

MANAGED=".zshrc"
PERSONAL=".zshrc.local"

# まず配布されていること
for f in .zshenv .zshrc .zimrc .zshrc.local .zimrc.local \
  .config/ghostty/config .config/ghostty/config.local \
  .config/xremap/config.yml .config/xremap/config.local.yml \
  .config/autostart/first-run-wizard.desktop \
  .claude/skills/herdr-ops/SKILL.md; do
  check_file "${HOME}/${f}" "既存ユーザーのホームに配られている: ${f}"
done

# 管理ファイルには「上書きされる」旨が書いてあること
check_contains "${HOME}/.zshrc" "上書きされる" \
  ".zshrc に上書きされる旨の注意書きがある"
check_contains "${HOME}/.zshrc" "\.zshrc\.local" \
  ".zshrc が個人設定ファイルを読み込む"
check_contains "${HOME}/.zimrc" "\.zimrc\.local" \
  ".zimrc が個人設定ファイルを読み込む"
check_contains "${HOME}/.config/ghostty/config" "^config-file = \?config\.local$" \
  "Ghostty の設定が config.local を任意読み込みする"

if ! sudo -n true 2>/dev/null; then
  diag "パスワードなし sudo が使えないため、上書き挙動の確認をスキップします。"
  assert_exit
fi

# ---------------------------------------------------------------------------
# 管理ファイルを書き換え、個人ファイルにも印を付けてから install.sh を再実行する
# ---------------------------------------------------------------------------

MARK="# mk-ubuntu-assert-mark"

printf '%s\n' "$MARK" >>"${HOME}/${MANAGED}"
printf '%s\n' "$MARK" >>"${HOME}/${PERSONAL}"

# リダイレクト先は呼び出し側ユーザーが書けるファイルなので sudo の影響外でよい
# shellcheck disable=SC2024
if ! sudo -n bash -lc "cd ${REPO_DIR} && ./install.sh 70-existing-users.sh" >/tmp/reapply.log 2>&1; then
  fail "70-existing-users.sh を再実行できた"
  tail -n 10 /tmp/reapply.log | while IFS= read -r l; do diag "$l"; done
  assert_exit
fi
pass "70-existing-users.sh を再実行できた"

if grep -q "$MARK" "${HOME}/${MANAGED}"; then
  fail "管理ファイル ${MANAGED} が上書きされて元に戻る"
  diag "書き換えが残っています。更新が行き渡らない状態です。"
else
  pass "管理ファイル ${MANAGED} が上書きされて元に戻る"
fi

if grep -q "$MARK" "${HOME}/${PERSONAL}"; then
  pass "個人ファイル ${PERSONAL} の内容が保持される"
else
  fail "個人ファイル ${PERSONAL} の内容が保持される"
  diag "個人の設定が消えています。"
fi

# 印を消して元の状態に戻す
sed -i "/${MARK}/d" "${HOME}/${PERSONAL}"

# 個人ファイルを消したら作り直されること
rm -f "${HOME}/${PERSONAL}"
sudo -n bash -lc "cd ${REPO_DIR} && ./install.sh 70-existing-users.sh" >/dev/null 2>&1
check_file "${HOME}/${PERSONAL}" "個人ファイルを消すと次の実行で作り直される"

assert_exit
