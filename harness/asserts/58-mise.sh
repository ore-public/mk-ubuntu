#!/usr/bin/env bash
# mise と Ruby ビルド依存の検証。
set -uo pipefail
# shellcheck source=harness/asserts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

MISE_VERSION="2026.8.6"

check "mise が /usr/local/bin にある" test -x /usr/local/bin/mise
check_cmd_output "mise のバージョンが ${MISE_VERSION}" "$MISE_VERSION" \
  /usr/local/bin/mise --version

# アーキに合ったバイナリが入っていること
case "$(dpkg --print-architecture)" in
  arm64) EXPECT_ELF="ARM aarch64" ;;
  amd64) EXPECT_ELF="x86-64" ;;
  *) EXPECT_ELF="" ;;
esac
check_cmd_output "mise が ${EXPECT_ELF} 向けである" "$EXPECT_ELF" file -L /usr/local/bin/mise

# Ruby のビルドとネイティブ拡張の gem に必要なパッケージ
for p in autoconf patch build-essential rustc libssl-dev libyaml-dev \
  libreadline-dev zlib1g-dev libgmp-dev libncurses-dev libffi-dev \
  libgdbm-dev libdb-dev uuid-dev pkg-config; do
  check "Ruby ビルド依存が導入済み: ${p}" \
    bash -c "dpkg-query -W -f='\${Status}' '${p}' 2>/dev/null | grep -q '^install ok installed$'"
done

# シェルでの有効化
check_contains /etc/skel/.zshrc "mise activate zsh" \
  "/etc/skel/.zshrc が mise を有効化する"

# 対話 zsh で mise が使える状態になること (実際に起動して確かめる)
check_cmd_output "対話 zsh で mise が使える" "$MISE_VERSION" \
  bash -c "zsh -i -c 'mise --version' 2>/dev/null"

# 何も指定していないディレクトリではシステムのコマンドが使われること
# (mise が無条件に PATH を奪っていないことの確認)
check_cmd_output "設定のない場所ではシステムの node が使われる" "^/usr/bin/node$" \
  bash -c "cd /tmp && zsh -i -c 'command -v node' 2>/dev/null"

assert_exit
