#!/usr/bin/env bash
# 新規ユーザー作成テスト。
# /etc/skel の継承、既定シェル、input グループの付与を実際に作って確かめる。
#
# 注意: adduser.conf の DSHELL / EXTRA_GROUPS を読むのは Debian の adduser であり
# useradd ではないため、ここでは adduser を使う。
set -uo pipefail
# shellcheck source=harness/asserts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TEST_USER="mkskeltest"

cleanup() {
  sudo -n deluser --remove-home "$TEST_USER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

if ! sudo -n true 2>/dev/null; then
  fail "パスワードなし sudo が使えないため新規ユーザーテストを実行できません"
  assert_exit
fi

cleanup

if ! sudo -n adduser --disabled-password --gecos "" "$TEST_USER" >/dev/null 2>&1; then
  fail "テストユーザー ${TEST_USER} の作成に失敗しました"
  assert_exit
fi
pass "テストユーザー ${TEST_USER} を作成できた"

HOME_DIR="/home/${TEST_USER}"

check_cmd_output "新規ユーザーの既定シェルが zsh" "/bin/zsh" \
  bash -c "getent passwd ${TEST_USER} | cut -d: -f7"
check "新規ユーザーが input グループに入っている" \
  bash -c "id -nG ${TEST_USER} | tr ' ' '\n' | grep -qx input"

# skel の継承
for f in .zshrc .zimrc .config/ghostty/config .config/xremap/config.yml \
  .config/autostart/first-run-wizard.desktop .claude/skills/herdr-ops/SKILL.md; do
  check "skel から継承されている: ${f}" sudo -n test -f "${HOME_DIR}/${f}"
done
check "skel から zimfw モジュールが継承されている" \
  sudo -n test -d "${HOME_DIR}/.zim/modules/fzf"

check "ホーム配下の所有者がテストユーザーである" \
  bash -c "[ \"\$(sudo -n stat -c %U ${HOME_DIR}/.zshrc)\" = ${TEST_USER} ]"

# 初回シェル起動で zimfw の init.zsh が生成されること (ネットワーク不要)。
# 端末がないため zle 関連の警告は出るが、これは無視してよい。
ZSH_OUT="$(sudo -n -u "$TEST_USER" env HOME="$HOME_DIR" zsh -i -c 'exit 0' 2>&1)"
ZSH_RC=$?
if [ "$ZSH_RC" -eq 0 ]; then
  pass "テストユーザーで対話 zsh が起動できた"
else
  fail "テストユーザーで対話 zsh の起動に失敗した"
  printf '%s\n' "$ZSH_OUT" | head -n 10 | while IFS= read -r l; do diag "$l"; done
fi

# zimfw の completion モジュールと Ubuntu の compinit の二重初期化がないこと
if printf '%s' "$ZSH_OUT" | grep -q "completion was already initialized"; then
  fail "compinit の二重初期化の警告が出ていない"
  diag "/etc/skel/.zshenv の skip_global_compinit=1 が効いていません。"
else
  pass "compinit の二重初期化の警告が出ていない"
fi
check "初回起動で ~/.zim/init.zsh が生成された" \
  sudo -n test -f "${HOME_DIR}/.zim/init.zsh"

assert_exit
