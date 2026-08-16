#!/usr/bin/env bash
#
# 本リポジトリが管理する状態のスナップショットを標準出力に出す。
# install.sh を 2 回実行して、この出力に差分がないことを冪等性の判定に使う。
#
# 出力にはタイムスタンプやキャッシュを含めない (内容ハッシュのみ)。
#
set -uo pipefail

# 内容ハッシュを出す。存在しない場合もその旨を出力して差分検出の対象にする。
hash_path() {
  local path="$1"
  if [ -L "$path" ]; then
    printf 'symlink %s -> %s\n' "$path" "$(readlink "$path")"
  elif [ -f "$path" ]; then
    printf 'file    %s %s %s\n' "$path" "$(stat -c '%a %U:%G' "$path")" \
      "$(sha256sum "$path" | cut -d' ' -f1)"
  elif [ -d "$path" ]; then
    printf 'dir     %s %s\n' "$path" "$(stat -c '%a %U:%G' "$path")"
  else
    printf 'missing %s\n' "$path"
  fi
}

hash_tree() {
  local root="$1"
  if [ ! -d "$root" ]; then
    printf 'missing %s\n' "$root"
    return 0
  fi
  # ディレクトリ配下の全ファイルの内容ハッシュ (パス順)
  find "$root" -type f -print0 2>/dev/null | sort -z |
    while IFS= read -r -d '' f; do
      printf 'tree    %s %s\n' "$f" "$(sha256sum "$f" | cut -d' ' -f1)"
    done
}

echo "=== 管理下のファイル ==="
for p in \
  /etc/adduser.conf \
  /etc/environment \
  /etc/udev/rules.d/99-input.rules \
  /etc/dconf/profile/user \
  /etc/xdg/mimeapps.list \
  /etc/xdg/xdg-terminals.list \
  /etc/xdg/gnome-xdg-terminals.list \
  /etc/xdg/ubuntu-xdg-terminals.list \
  /etc/profile.d/mk-ubuntu-playwright.sh \
  /etc/apt/keyrings/brave-browser-archive-keyring.gpg \
  /etc/apt/sources.list.d/brave-browser-release.sources \
  /usr/share/keyrings/1password-archive-keyring.gpg \
  /etc/apt/sources.list.d/1password.sources \
  /etc/apt/keyrings/docker.gpg \
  /etc/apt/sources.list.d/docker.sources \
  /etc/systemd/user/xremap.service \
  /etc/systemd/user/default.target.wants/xremap.service \
  /usr/local/bin/xremap \
  /usr/local/bin/herdr \
  /usr/local/bin/opencode \
  /usr/local/bin/first-run-wizard \
  /usr/local/bin/mise \
  /usr/local/bin/vicinae \
  /etc/systemd/user/vicinae.service \
  /etc/systemd/user/default.target.wants/vicinae.service \
  /opt/vicinae/.installed-version \
  /usr/local/bin/bat \
  /usr/local/share/zimfw/zimfw.zsh; do
  hash_path "$p"
done

echo
echo "=== カスタムキーバインドの登録簿 ==="
hash_tree /var/lib/mk-ubuntu/custom-keybindings

echo
echo "=== dconf のシステム既定値 ==="
hash_tree /etc/dconf/db/local.d
# バイナリ DB の中身は dconf update の生成結果なので、内容ではなく存在だけを見る
[ -f /etc/dconf/db/local ] && echo "dconf-db local PRESENT" || echo "dconf-db local ABSENT"

echo
echo "=== /etc/skel ==="
hash_tree /etc/skel/.config
hash_tree /etc/skel/.claude
hash_path /etc/skel/.zshenv
hash_path /etc/skel/.zshrc
hash_path /etc/skel/.zimrc
# .zim/modules は git clone なので個別ファイルではなくモジュール名の一覧で比較する
find /etc/skel/.zim/modules -maxdepth 1 -mindepth 1 -type d 2>/dev/null |
  sort | sed 's/^/zimmodule /'
[ -e /etc/skel/.zim/init.zsh ] && echo "skel-init-zsh PRESENT" || echo "skel-init-zsh ABSENT"

echo
echo "=== GNOME 拡張 ==="
hash_tree /usr/share/gnome-shell/extensions/xremap@k0kubun.com
hash_tree /usr/share/gnome-shell/extensions/follow-moved-windows@mk-ubuntu

echo
echo "=== 既存ユーザーへ配った管理ファイル ==="
# 70-existing-users.sh が毎回上書きするので、2 回目の実行で内容が
# 変わらないことをここで確かめる (個人ファイルは対象外)
while IFS=: read -r _user _ _uid _ _ _home _shell; do
  if [ "$_uid" -ge 1000 ] && [ "$_uid" -lt 60000 ] && [ -d "$_home" ]; then
    for f in .zshenv .zshrc .zimrc \
      .config/ghostty/config .config/xremap/config.yml \
      .config/autostart/first-run-wizard.desktop \
      .claude/skills/herdr-ops/SKILL.md; do
      hash_path "${_home}/${f}"
    done
  fi
done </etc/passwd

echo
echo "=== 導入済み apt パッケージ ==="
dpkg-query -W -f='${binary:Package} ${Version}\n' 2>/dev/null | sort

echo
echo "=== npm グローバルパッケージ ==="
if command -v npm >/dev/null 2>&1; then
  npm ls -g --depth=0 2>/dev/null | tail -n +2 | sort
fi

echo
echo "=== Playwright ブラウザ ==="
find /opt/playwright-browsers -maxdepth 1 -mindepth 1 2>/dev/null | sort

echo
echo "=== update-alternatives ==="
for alt in x-terminal-emulator x-www-browser gnome-www-browser; do
  printf '%s -> %s\n' "$alt" \
    "$(update-alternatives --query "$alt" 2>/dev/null | awk -F': ' '/^Value:/ {print $2}')"
done

echo
echo "=== バージョン ==="
for cmd in "xremap --version" "herdr --version" "opencode --version" \
  "claude --version" "copilot --version" "ghostty --version" "node --version"; do
  printf '%s: %s\n' "$cmd" "$($cmd 2>/dev/null | head -n 1 || echo '取得失敗')"
done
