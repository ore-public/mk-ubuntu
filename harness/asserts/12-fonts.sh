#!/usr/bin/env bash
# フォント (Moralerspace Neon HW) の検証。
set -uo pipefail
# shellcheck source=harness/asserts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

FONT_DIR="/usr/local/share/fonts/moralerspace"
FONT_FAMILY="Moralerspace Neon HW"

check_dir "$FONT_DIR"
for style in Regular Bold Italic BoldItalic; do
  check_file "${FONT_DIR}/MoralerspaceNeonHW-${style}.ttf"
done

# 指定した variant だけを入れていること (zip には全 variant が入っているが
# 使うのは Neon HW だけなので、他が混ざっていたら取り出し方が間違っている)
check "Neon HW 以外の variant を入れていない" \
  bash -c "! ls ${FONT_DIR} 2>/dev/null | grep -qvE '^MoralerspaceNeonHW-'"
check "ファイル数が 4 つ" \
  bash -c "[ \"\$(find ${FONT_DIR} -name '*.ttf' | wc -l)\" -eq 4 ]"

# fontconfig から引けること (ここが通らないとアプリがフォントを見つけられない)
check "fontconfig が ${FONT_FAMILY} を認識している" \
  bash -c "fc-list : family | tr ',' '\n' | grep -qx '${FONT_FAMILY}'"
check_cmd_output "4 つのスタイルすべてが引ける" "Regular" \
  bash -c "fc-list : family style | grep -c '${FONT_FAMILY}' | grep -q '^4$' && echo Regular"

# Ghostty がこのフォントを使う設定になっていること
check_contains /etc/skel/.config/ghostty/config \
  "^font-family = \"${FONT_FAMILY}\"$" \
  "Ghostty の設定が ${FONT_FAMILY} を指している"

# 実際に Ghostty がそのフォントを解決できること
# (設定に書いてあってもフォントが無ければ別のフォントに落ちるため)
if command -v ghostty >/dev/null 2>&1; then
  check_cmd_output "Ghostty が ${FONT_FAMILY} を一覧に持っている" "$FONT_FAMILY" \
    bash -c "ghostty +list-fonts 2>/dev/null | grep -F '${FONT_FAMILY}'"
fi

assert_exit
