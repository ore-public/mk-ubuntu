#!/usr/bin/env bash
#
# フォント
#
# ターミナルで使う Moralerspace Neon HW を導入する。
# Monaspace (英字) と IBM Plex Sans JP (日本語) を合成した
# 日本語プログラミングフォントで、HW は日本語を半角幅で組む版。
#
# 配布 zip には Argon / Krypton / Neon / Radon / Xenon の全 variant が
# 入っていて 102MB あるが、使うのは Neon HW だけなので
# 該当する 4 ファイル (約 32MB) だけを取り出して置く。
#
# システム全体に置くので、どのユーザーからも使える。
# 各自で別のフォントを使いたい場合は ~/.config/ghostty/config.local で
# font-family を上書きできる (README の「自分好みに設定を変える」を参照)。
#
set -euo pipefail

MODULE_NAME="12-fonts"
# shellcheck source=lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

MORALERSPACE_VERSION="v2.0.0"
MORALERSPACE_URL="https://github.com/yuru7/moralerspace/releases/download/${MORALERSPACE_VERSION}/MoralerspaceHW_${MORALERSPACE_VERSION}.zip"
MORALERSPACE_SHA256="500a7774297c829265ebd472b6d8c1159cfb3e9daa4ca0570170af541b991b7d"

# zip の中の取り出したいファイル (Neon の HW 版だけ)
MORALERSPACE_PATTERN="MoralerspaceNeonHW-*.ttf"
MORALERSPACE_STYLES=(Regular Bold Italic BoldItalic)

FONT_DIR="/usr/local/share/fonts/moralerspace"
CACHE_DIR="/var/cache/mk-ubuntu"

# 期待するファイルが揃っているか
fonts_installed() {
  local style
  for style in "${MORALERSPACE_STYLES[@]}"; do
    [ -f "${FONT_DIR}/MoralerspaceNeonHW-${style}.ttf" ] || return 1
  done
  return 0
}

install_moralerspace() {
  if fonts_installed; then
    log "変更なし: ${FONT_DIR} (Moralerspace Neon HW 導入済み)"
    return 0
  fi

  local cached extract_dir
  cached="${CACHE_DIR}/MoralerspaceHW_${MORALERSPACE_VERSION}.zip"

  install -d "$CACHE_DIR"
  download_verify "$MORALERSPACE_URL" "$MORALERSPACE_SHA256" "$cached"

  extract_dir="$(mktemp -d)"
  # zip 全体ではなく Neon HW だけを展開する
  unzip -q -j -o "$cached" "*/${MORALERSPACE_PATTERN}" -d "$extract_dir" ||
    { rm -rf "$extract_dir"; die "フォントの展開に失敗しました。"; }

  local style
  for style in "${MORALERSPACE_STYLES[@]}"; do
    [ -f "${extract_dir}/MoralerspaceNeonHW-${style}.ttf" ] ||
      { rm -rf "$extract_dir"; die "zip に MoralerspaceNeonHW-${style}.ttf がありません。"; }
  done

  install -d "$FONT_DIR"
  install -m 0644 "${extract_dir}"/MoralerspaceNeonHW-*.ttf "$FONT_DIR/"
  rm -rf "$extract_dir"

  log "配置: ${FONT_DIR} ($(find "$FONT_DIR" -name '*.ttf' | wc -l) ファイル)"
}

main() {
  require_root

  apt_install fontconfig

  install_moralerspace

  # ディレクトリを指定すると、その場の fc-list にすぐ反映されないことがある。
  # 全体を作り直す方が確実 (数秒で終わる)。
  log "フォントキャッシュを更新します"
  fc-cache -f >/dev/null 2>&1 || warn "fc-cache に失敗しました。"

  if fc-list 2>/dev/null | grep -q "Moralerspace Neon HW"; then
    log "フォントが利用可能です: Moralerspace Neon HW"
  else
    warn "fc-list で Moralerspace Neon HW を確認できませんでした。"
  fi
}

main "$@"
