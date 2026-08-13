#!/usr/bin/env bash
# アーキテクチャ分岐の検証。
# 検証 VM は arm64 なので、配置された外部バイナリが aarch64 であることを確認する。
set -uo pipefail
# shellcheck source=harness/asserts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

DEB_ARCH="$(dpkg --print-architecture)"
UNAME_ARCH="$(uname -m)"

diag "dpkg --print-architecture = ${DEB_ARCH} / uname -m = ${UNAME_ARCH}"

check "アーキテクチャが amd64 か arm64 である" \
  bash -c "[ '${DEB_ARCH}' = amd64 ] || [ '${DEB_ARCH}' = arm64 ]"

# 想定 ELF マシン名
case "$DEB_ARCH" in
  arm64) EXPECT_ELF="ARM aarch64" ;;
  amd64) EXPECT_ELF="x86-64" ;;
  *) EXPECT_ELF="" ;;
esac

for bin in /usr/local/bin/xremap /usr/local/bin/herdr /usr/local/bin/opencode; do
  if [ ! -x "$bin" ]; then
    fail "${bin} が実行可能ファイルとして存在する"
    continue
  fi
  check_cmd_output "${bin} が ${EXPECT_ELF} 向けである" "$EXPECT_ELF" file -L "$bin"
done

assert_exit
