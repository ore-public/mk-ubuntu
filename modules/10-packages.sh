#!/usr/bin/env bash
#
# F1. パッケージ基盤
#
# apt から基礎パッケージを導入する。外部 apt リポジトリは追加しない
# (Brave のみ 15-brave.sh で例外的に追加する)。
#
set -euo pipefail

MODULE_NAME="10-packages"
# shellcheck source=lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

# 要件 F1 で指定されたパッケージ
PACKAGES_REQUIRED=(
  zsh
  fzf
  bat
  curl
  git
  build-essential
  ghostty
  gnome-shell-extensions
  gnome-browser-connector
)

# 後続モジュールと「実現する体験」のために追加するパッケージ。
# 追加理由は README の「設計判断」節に記載。
PACKAGES_EXTRA=(
  ripgrep           # zimfw の fzf モジュールがファイル列挙に必要とする
  unzip             # xremap / GNOME 拡張の zip 展開
  ca-certificates   # 外部バイナリ取得時の TLS 検証
  dconf-cli         # dconf update / gsettings によるシステム既定値設定
  xdg-terminal-exec # 既定ターミナルの決定機構 (25-ghostty.sh で使用)
  xdg-utils         # xdg-settings / xdg-mime
  jq                # 検証スクリプトと first-run-wizard での JSON 読み取り
)

main() {
  require_root

  # ghostty / bat / fzf / nodejs はいずれも universe にある。
  # Ubuntu Desktop の既定では有効なので、無効なときだけ有効化する。
  if apt-cache policy 2>/dev/null | grep -q "/universe"; then
    log "universe コンポーネントは有効です"
  elif command -v add-apt-repository >/dev/null 2>&1; then
    log "universe コンポーネントを有効化します"
    add-apt-repository -y universe
    APT_UPDATED=0
  else
    warn "universe が無効で add-apt-repository もありません。導入に失敗する可能性があります。"
  fi

  apt_install "${PACKAGES_REQUIRED[@]}" "${PACKAGES_EXTRA[@]}"

  # Ubuntu の bat の実体は batcat。zimfw の fzf モジュールなど
  # 「bat」というコマンド名を探すツールのために系統リンクを置く。
  # 対話シェル用の alias は 20-zsh-zimfw.sh の .zshrc 側で別途設定する。
  if [ -x /usr/bin/batcat ]; then
    if [ "$(readlink /usr/local/bin/bat 2>/dev/null || true)" = "/usr/bin/batcat" ]; then
      log "変更なし: /usr/local/bin/bat"
    elif [ -e /usr/local/bin/bat ] && [ ! -L /usr/local/bin/bat ]; then
      warn "/usr/local/bin/bat がシンボリックリンク以外で存在するため上書きしません。"
    else
      install -d /usr/local/bin
      ln -sfn /usr/bin/batcat /usr/local/bin/bat
      log "配置: /usr/local/bin/bat -> /usr/bin/batcat"
    fi
  else
    warn "/usr/bin/batcat が見つかりません。bat の導入を確認してください。"
  fi

  log "導入済みバージョン:"
  ghostty --version 2>/dev/null | head -n 1 || warn "ghostty のバージョン取得に失敗しました。"
  fzf --version 2>/dev/null | head -n 1 || warn "fzf のバージョン取得に失敗しました。"
  batcat --version 2>/dev/null | head -n 1 || true
}

main "$@"
