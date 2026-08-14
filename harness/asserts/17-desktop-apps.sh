#!/usr/bin/env bash
# ベンダー公式配布のデスクトップアプリ (Discord / Zoom / 1Password / Dropbox) の検証。
#
# 4 つとも公式が amd64 版しか配布していないため、arm64 では
# 「導入されていないこと」と「スキップの判断が正しいこと」だけを確かめる。
set -uo pipefail
# shellcheck source=harness/asserts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ARCH="$(dpkg --print-architecture)"
APPS="discord zoom 1password dropbox"

installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "^install ok installed$"
}

if [ "$ARCH" != "amd64" ]; then
  diag "アーキテクチャは ${ARCH}。公式配布が amd64 のみのため導入されない想定。"
  for p in $APPS; do
    if installed "$p"; then
      fail "${ARCH} では ${p} を導入しない"
    else
      pass "${ARCH} では ${p} を導入しない"
    fi
  done
  # 外部リポジトリも足していないこと
  check "1Password の apt リポジトリを追加していない" \
    test ! -f /etc/apt/sources.list.d/1password.sources
  assert_exit
fi

# --- ここから amd64 のみ ---
for p in $APPS; do
  check "導入済み: ${p}" bash -c "dpkg-query -W -f='\${Status}' '${p}' 2>/dev/null | grep -q '^install ok installed$'"
done

# 実行ファイルが入っていること
check "discord コマンドがある" bash -c "command -v discord"
check "zoom コマンドがある" bash -c "command -v zoom"
check "1password が配置されている" bash -c "test -x /opt/1Password/1password || command -v 1password"
check "dropbox コマンドがある" bash -c "command -v dropbox"

# デスクトップから起動できること
for d in discord.desktop Zoom.desktop 1password.desktop dropbox.desktop; do
  check "デスクトップエントリがある: ${d}" \
    bash -c "test -f /usr/share/applications/${d}"
done

# 1Password は導入後、パッケージ自身が apt リポジトリ定義を管理する。
# こちらは足場を作るだけなので、確認するのは「パッケージ側の自動更新チャンネルが
# 出来上がっていること」。
check_file /usr/share/keyrings/1password-archive-keyring.gpg \
  "1Password が自前の keyring を配置している"
check_file /etc/apt/sources.list.d/1password.sources
check_contains /etc/apt/sources.list.d/1password.sources \
  "^Signed-By: /usr/share/keyrings/1password-archive-keyring.gpg$" \
  "1Password の apt チャンネルがパッケージ管理下になっている"
check "導入用の足場の keyring を残していない" \
  test ! -f /etc/apt/keyrings/1password-archive-keyring.gpg

# Dropbox はバージョン固定
check_cmd_output "Dropbox が固定したバージョンである" "2026\.05\.06" \
  bash -c "dpkg-query -W -f='\${Version}' dropbox"

assert_exit
