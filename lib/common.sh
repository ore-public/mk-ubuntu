#!/usr/bin/env bash
# 全モジュール共通のヘルパー。各モジュールの先頭で source する。
# このファイル自体は単体では実行しない。

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# ---------------------------------------------------------------------------
# ログ
# ---------------------------------------------------------------------------

MODULE_NAME="${MODULE_NAME:-$(basename "${BASH_SOURCE[1]:-common}" .sh)}"

log() {
  printf '[%s] %s\n' "$MODULE_NAME" "$*"
}

warn() {
  printf '[%s] WARN: %s\n' "$MODULE_NAME" "$*" >&2
}

die() {
  printf '[%s] ERROR: %s\n' "$MODULE_NAME" "$*" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# 前提チェック
# ---------------------------------------------------------------------------

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    die "root 権限が必要です。sudo を付けて実行してください。"
  fi
}

# 対象は Ubuntu 26.04 のみ。他バージョンでは警告するが停止はしない
# (開発中に別バージョンで静的検証したい場合があるため)。
check_target_release() {
  if [ ! -r /etc/os-release ]; then
    warn "/etc/os-release が読めません。対象リリースの確認をスキップします。"
    return 0
  fi
  # shellcheck disable=SC1091
  . /etc/os-release
  if [ "${ID:-}" != "ubuntu" ] || [ "${VERSION_ID:-}" != "26.04" ]; then
    warn "対象は Ubuntu 26.04 です (検出: ${ID:-unknown} ${VERSION_ID:-unknown})。"
  fi
}

# ---------------------------------------------------------------------------
# アーキテクチャ
# ---------------------------------------------------------------------------

# dpkg 表記 (amd64 / arm64) を返す
deb_arch() {
  dpkg --print-architecture
}

# 与えられた amd64 用の値と arm64 用の値のうち、現在のアーキに対応する方を出力する
pick_arch() {
  local amd64_value="$1" arm64_value="$2" arch
  arch="$(deb_arch)"
  case "$arch" in
    amd64) printf '%s\n' "$amd64_value" ;;
    arm64) printf '%s\n' "$arm64_value" ;;
    *) die "未対応のアーキテクチャです: $arch (amd64 / arm64 のみ対応)" ;;
  esac
}

# ---------------------------------------------------------------------------
# ダウンロード + チェックサム検証
# ---------------------------------------------------------------------------

# download_verify <url> <sha256> <dest>
# dest が既に存在し、チェックサムが一致していれば何もしない (冪等)。
download_verify() {
  local url="$1" sha256="$2" dest="$3" tmp

  if [ -f "$dest" ] && printf '%s  %s\n' "$sha256" "$dest" | sha256sum -c --status; then
    log "既に取得済み (チェックサム一致): $dest"
    return 0
  fi

  tmp="$(mktemp)"
  log "ダウンロード: $url"
  if ! curl -fsSL --retry 3 --retry-delay 2 -o "$tmp" "$url"; then
    rm -f "$tmp"
    die "ダウンロードに失敗しました: $url"
  fi

  if ! printf '%s  %s\n' "$sha256" "$tmp" | sha256sum -c --status; then
    local actual
    actual="$(sha256sum "$tmp" | cut -d' ' -f1)"
    rm -f "$tmp"
    die "チェックサムが一致しません: $url (期待 $sha256 / 実際 $actual)"
  fi

  install -d "$(dirname "$dest")"
  mv "$tmp" "$dest"
  chmod 0644 "$dest"
  log "取得完了: $dest"
}

# ---------------------------------------------------------------------------
# ファイル配置
# ---------------------------------------------------------------------------

# install_file <src> <dest> [mode]
# 内容が同一なら書き込まない (ログを静かに保ち、mtime を無意味に更新しない)。
install_file() {
  local src="$1" dest="$2" mode="${3:-0644}"
  install -d "$(dirname "$dest")"
  if [ -f "$dest" ] && cmp -s "$src" "$dest"; then
    chmod "$mode" "$dest"
    log "変更なし: $dest"
    return 0
  fi
  install -m "$mode" "$src" "$dest"
  log "配置: $dest"
}

# write_file <dest> [mode] < 内容
# 標準入力の内容を dest に書く。内容が同一なら書き込まない。
write_file() {
  local dest="$1" mode="${2:-0644}" tmp
  tmp="$(mktemp)"
  cat >"$tmp"
  install -d "$(dirname "$dest")"
  if [ -f "$dest" ] && cmp -s "$tmp" "$dest"; then
    rm -f "$tmp"
    chmod "$mode" "$dest"
    log "変更なし: $dest"
    return 0
  fi
  install -m "$mode" "$tmp" "$dest"
  rm -f "$tmp"
  log "配置: $dest"
}

# ---------------------------------------------------------------------------
# 設定ファイルの key=value 書き換え (adduser.conf など)
# ---------------------------------------------------------------------------

# set_conf_key <file> <key> <value>
# 「KEY=VALUE」形式の行を置き換える。コメントアウトされた行があればそれを活かす。
# 該当行がなければ末尾に追記する。何度実行しても行は増えない。
set_conf_key() {
  local file="$1" key="$2" value="$3" desired count tmp
  desired="${key}=${value}"

  [ -f "$file" ] || die "設定ファイルが見つかりません: $file"

  count="$(grep -c -E "^${key}=" "$file" || true)"
  if [ "$count" = "1" ] && [ "$(grep -m1 -E "^${key}=" "$file")" = "$desired" ]; then
    log "変更なし: ${file} の ${key}"
    return 0
  fi

  # sed の方言差を避けるため awk で書き換える。
  # 1) 有効な KEY= 行があれば最初の 1 行を置換し、残りは削除する
  # 2) なければコメントアウトされた #KEY= 行を活かす
  # 3) どちらもなければ末尾に追記する
  tmp="$(mktemp)"
  awk -v key="$key" -v desired="$desired" '
    BEGIN { done = 0 }
    $0 ~ "^" key "=" {
      if (!done) { print desired; done = 1 }
      next
    }
    !done && $0 ~ "^#[ \t]*" key "=" { print desired; done = 1; next }
    { print }
    END { if (!done) print desired }
  ' "$file" >"$tmp"

  # 元ファイルの権限と所有者を保つため、置き換えではなく内容の上書きにする
  cat "$tmp" >"$file"
  rm -f "$tmp"
  log "設定: ${file} の ${key}=${value}"
}

# ---------------------------------------------------------------------------
# apt
# ---------------------------------------------------------------------------

APT_UPDATED=0

# 起動直後は unattended-upgrades が dpkg のロックを握っていることが多い。
# APT 自身にロック待ちをさせる (待たないと "Could not get lock" で即失敗する)。
APT_OPTS=(-o "DPkg::Lock::Timeout=600")

# 他のパッケージ処理が終わるまで待つ。
# apt-get check はロックを取るので、ロック待ちの実装をそのまま利用できる。
wait_for_apt_lock() {
  if ! apt-get "${APT_OPTS[@]}" check -qq >/dev/null 2>&1; then
    warn "パッケージ管理のロック待ちに失敗しました。処理を続行します。"
  fi
}

apt_update_once() {
  if [ "$APT_UPDATED" -eq 0 ]; then
    log "apt update を実行します"
    apt-get "${APT_OPTS[@]}" update -qq
    APT_UPDATED=1
  fi
}

# apt_install <package>...
# 未導入のものだけを導入する。全て導入済みなら apt update すら行わない。
apt_install() {
  local missing=() pkg
  for pkg in "$@"; do
    if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "^install ok installed$"; then
      missing+=("$pkg")
    fi
  done

  if [ "${#missing[@]}" -eq 0 ]; then
    log "導入済み: $*"
    return 0
  fi

  apt_update_once
  log "apt install: ${missing[*]}"
  apt-get "${APT_OPTS[@]}" install -y -qq --no-install-recommends "${missing[@]}"
}

# ---------------------------------------------------------------------------
# dconf
# ---------------------------------------------------------------------------

DCONF_DB_DIR=/etc/dconf/db/local.d
DCONF_PROFILE=/etc/dconf/profile/user

# dconf のシステム既定値プロファイルを用意する
ensure_dconf_profile() {
  write_file "$DCONF_PROFILE" 0644 <<'EOF'
user-db:user
system-db:local
EOF
  install -d "$DCONF_DB_DIR"
}

# dconf データベースを再構築する。同じ内容なら dconf update は差分を生まない。
dconf_update() {
  log "dconf update を実行します"
  dconf update
}

# GNOME のカスタムキーバインドも enabled-extensions と同じ事情がある。
# custom-keybindings は 1 つのキーにパスの配列を並べる形式なので、
# モジュールごとに別ファイルへ書くとお互いを上書きしてしまう。
# そこで「登録簿」を 1 か所に持ち、そこから dconf ファイルを毎回作り直す。
DCONF_CUSTOM_KEYBINDINGS_FILE="${DCONF_DB_DIR}/35-custom-keybindings"
CUSTOM_KEYBINDING_STATE_DIR="/var/lib/mk-ubuntu/custom-keybindings"
CUSTOM_KEYBINDING_BASE_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings"

# 登録簿から dconf のシステム既定値ファイルを作り直す。
# 割り当てる customN の番号は ID の辞書順で決まるので、何度実行しても同じ結果になる。
regenerate_custom_keybindings() {
  local ids=() id index=0 paths=""

  while IFS= read -r id; do
    [ -n "$id" ] && ids+=("$id")
  done < <(find "$CUSTOM_KEYBINDING_STATE_DIR" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort)

  if [ "${#ids[@]}" -eq 0 ]; then
    return 0
  fi

  for index in $(seq 0 $((${#ids[@]} - 1))); do
    [ -n "$paths" ] && paths="${paths}, "
    paths="${paths}'${CUSTOM_KEYBINDING_BASE_PATH}/custom${index}/'"
  done

  {
    printf '%s\n' \
      '# Mac 風の操作のために追加したカスタムキーバインド。' \
      '# custom-keybindings は 1 キーに全パスを並べる形式なので、' \
      '# 全モジュール分をこのファイルにまとめて生成している。' \
      '[org/gnome/settings-daemon/plugins/media-keys]' \
      "custom-keybindings=[${paths}]"

    index=0
    for id in "${ids[@]}"; do
      {
        read -r kb_name
        read -r kb_command
        read -r kb_binding
      } <"${CUSTOM_KEYBINDING_STATE_DIR}/${id}"
      printf '\n[org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom%d]\n' "$index"
      printf "name='%s'\ncommand='%s'\nbinding='%s'\n" "$kb_name" "$kb_command" "$kb_binding"
      index=$((index + 1))
    done
  } | write_file "$DCONF_CUSTOM_KEYBINDINGS_FILE" 0644
}

# dconf_set_custom_keybinding <ID> <表示名> <コマンド> <キー>
# ID は登録簿のファイル名になる。同じ ID で呼び直せば内容が置き換わる。
dconf_set_custom_keybinding() {
  local id="$1" name="$2" command="$3" binding="$4"
  ensure_dconf_profile
  install -d "$CUSTOM_KEYBINDING_STATE_DIR"
  write_file "${CUSTOM_KEYBINDING_STATE_DIR}/${id}" 0644 <<EOF
${name}
${command}
${binding}
EOF
  regenerate_custom_keybindings
}

# GNOME Shell の enabled-extensions は 1 つのキーに全 UUID を並べる形式なので、
# 複数のモジュールが個別に書くとお互いを上書きしてしまう。
# そのため、このキーだけは専用ファイル 1 つで管理し、和集合を取って書き換える。
DCONF_EXTENSIONS_FILE="${DCONF_DB_DIR}/30-extensions"

# dconf_enable_extension <uuid>...
dconf_enable_extension() {
  local current new
  ensure_dconf_profile

  # 既定値 (Ubuntu が gschema override で入れている拡張) を土台にする。
  # 2 回目以降は自分が書いた値が返るので、和集合を取る限り結果は変わらない。
  if command -v gsettings >/dev/null 2>&1 &&
    current="$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null)"; then
    :
  else
    warn "org.gnome.shell スキーマを読めません。既定の拡張一覧なしで書き込みます。"
    current="@as []"
  fi

  new="$(python3 - "$current" "$@" <<'PY'
import re
import sys

current = sys.argv[1]
wanted = sys.argv[2:]
uuids = set(re.findall(r"'([^']*)'", current))
uuids.update(wanted)
print("[" + ", ".join("'%s'" % u for u in sorted(uuids)) + "]")
PY
  )"

  write_file "$DCONF_EXTENSIONS_FILE" 0644 <<EOF
# GNOME Shell で有効化する拡張の一覧。
# このキーは 1 か所でしか管理できないため、全モジュール分をここにまとめる。
[org/gnome/shell]
enabled-extensions=${new}
EOF
}

# ---------------------------------------------------------------------------
# リポジトリ内のパス
# ---------------------------------------------------------------------------

# lib/common.sh の 1 つ上がリポジトリルート
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT
