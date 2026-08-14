#!/usr/bin/env bash
#
# Ubuntu 26.04 LTS (Resolute Raccoon) Desktop を
# 「Mac 風操作 + AI エージェント開発環境」の状態にするプロビジョナ。
#
#   sudo ./install.sh                 # 全モジュールを番号順に適用
#   sudo ./install.sh 30-xremap.sh    # 指定モジュールだけを適用
#   sudo ./install.sh --list          # モジュール一覧を表示
#
# 何度実行しても安全 (冪等)。
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_NAME="install"

# shellcheck source=lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh"

usage() {
  cat <<'EOF'
使い方:
  sudo ./install.sh [オプション] [モジュール名...]

オプション:
  --list        適用対象のモジュール一覧を表示して終了する
  -h, --help    このヘルプを表示する

モジュール名は modules/ 配下のファイル名 (例: 30-xremap.sh)。
番号プレフィックスだけ (例: 30) でも指定できる。
EOF
}

list_modules() {
  local f
  for f in "${SCRIPT_DIR}"/modules/*.sh; do
    [ -e "$f" ] || continue
    basename "$f"
  done
}

# 引数で指定されたモジュール名を modules/ 配下の実パスへ解決する
resolve_module() {
  local want="$1" f
  for f in "${SCRIPT_DIR}"/modules/*.sh; do
    [ -e "$f" ] || continue
    case "$(basename "$f")" in
      "$want" | "${want}.sh" | "${want}-"*) printf '%s\n' "$f"; return 0 ;;
    esac
  done
  return 1
}

main() {
  local selected=() args=() arg path

  for arg in "$@"; do
    case "$arg" in
      -h | --help) usage; return 0 ;;
      --list) list_modules; return 0 ;;
      -*) die "不明なオプションです: $arg" ;;
      *) args+=("$arg") ;;
    esac
  done

  require_root
  check_target_release

  if [ "${#args[@]}" -gt 0 ]; then
    for arg in "${args[@]}"; do
      if ! path="$(resolve_module "$arg")"; then
        die "モジュールが見つかりません: $arg"
      fi
      selected+=("$path")
    done
  else
    for path in "${SCRIPT_DIR}"/modules/*.sh; do
      [ -e "$path" ] || continue
      selected+=("$path")
    done
  fi

  [ "${#selected[@]}" -gt 0 ] || die "適用するモジュールがありません。"

  # 起動直後は unattended-upgrades が動いていることが多い。
  # 先に終わるのを待たないと、途中の apt が "Could not get lock" で失敗する。
  log "パッケージ管理のロックが空くのを待ちます"
  wait_for_apt_lock

  log "対象アーキテクチャ: $(deb_arch)"
  log "適用モジュール数: ${#selected[@]}"

  for path in "${selected[@]}"; do
    printf '\n===== %s =====\n' "$(basename "$path")"
    bash "$path"
  done

  printf '\n'
  log "全モジュールの適用が完了しました。"
  log "再起動後、初回ログイン時に first-run-wizard が自動起動します。"
}

main "$@"
