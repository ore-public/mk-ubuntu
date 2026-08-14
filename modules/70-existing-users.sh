#!/usr/bin/env bash
#
# 既存ユーザーへの設定の行き渡らせ
#
# /etc/skel が効くのは「これから作られるユーザー」だけなので、
# install.sh を実行した本人を含む既存ユーザーには何も届かない。
# このモジュールが /etc/skel の内容を既存ユーザーのホームに配る。
#
# 配り方は 2 種類に分かれる:
#
#   管理ファイル … 毎回そのまま上書きする。
#                  こうしないと、このリポジトリを更新して再実行しても
#                  運用中の PC に変更が反映されない。
#   個人ファイル … 無いときだけ作る。以後は一切触らない。
#                  利用者はこちらに自分の設定を書く。
#
# どのファイルが個人ファイルかは PERSONAL_FILES で定義する。
# 管理ファイル側からは必ず対応する個人ファイルを読み込むようにしてあるので、
# 上書きされても利用者の設定は失われない。
#
# ログインシェルの変更だけは行わず、chsh の案内にとどめる。
#
set -euo pipefail

MODULE_NAME="70-existing-users"
# shellcheck source=lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

SKEL=/etc/skel

# 個人ファイル (/etc/skel からの相対パス)。
# 無いときだけ作り、以後は上書きしない。
PERSONAL_FILES=(
  ".zshrc.local"
  ".zimrc.local"
  ".config/ghostty/config.local"
  ".config/xremap/config.local.yml"
)

# 上書きの対象にしないディレクトリ (/etc/skel からの相対パス)。
# .zim/modules は git clone した実体で設定ではないため、
# 不足分を補うだけにして毎回コピーし直さない。
SEED_ONLY_DIRS=(
  ".zim"
)

is_personal_file() {
  local rel="$1" p
  for p in "${PERSONAL_FILES[@]}"; do
    [ "$rel" = "$p" ] && return 0
  done
  return 1
}

is_seed_only() {
  local rel="$1" d
  for d in "${SEED_ONLY_DIRS[@]}"; do
    case "$rel" in
      "$d" | "$d"/*) return 0 ;;
    esac
  done
  return 1
}

# 対象は通常のログインユーザー (UID 1000-59999) でホームがあるもの
list_regular_users() {
  local user uid home shell
  while IFS=: read -r user _ uid _ _ home shell; do
    case "$shell" in
      */nologin | */false) continue ;;
    esac
    if [ "$uid" -ge 1000 ] && [ "$uid" -lt 60000 ] && [ -d "$home" ]; then
      printf '%s\t%s\t%s\n' "$user" "$home" "$shell"
    fi
  done </etc/passwd
}

# copy_as_user <ユーザー> <コピー元> <コピー先>
# 対象ユーザー自身として実行することで所有者が自動的に正しくなる。
copy_as_user() {
  local user="$1" src="$2" dest="$3"
  runuser -u "$user" -- install -d "$(dirname "$dest")"
  runuser -u "$user" -- cp --preserve=mode "$src" "$dest"
}

seed_skel_into_home() {
  local user="$1" home="$2"
  local rel src dest updated=0 created=0 kept=0

  while IFS= read -r rel; do
    src="${SKEL}/${rel}"
    dest="${home}/${rel}"

    if is_seed_only "$rel"; then
      # 不足しているものだけ補う
      if [ ! -e "$dest" ]; then
        copy_as_user "$user" "$src" "$dest"
        created=$((created + 1))
      fi
      continue
    fi

    if is_personal_file "$rel"; then
      # 個人ファイル: 無いときだけ作る
      if [ ! -e "$dest" ]; then
        copy_as_user "$user" "$src" "$dest"
        created=$((created + 1))
      else
        kept=$((kept + 1))
      fi
      continue
    fi

    # 管理ファイル: 毎回そのまま上書きする
    if [ -f "$dest" ] && cmp -s "$src" "$dest"; then
      continue
    fi
    copy_as_user "$user" "$src" "$dest"
    updated=$((updated + 1))
  done < <(cd "$SKEL" && find . -type f -printf '%P\n' | sort)

  if [ "$updated" -eq 0 ] && [ "$created" -eq 0 ]; then
    log "変更なし: ${home} (管理ファイルは最新、個人ファイル ${kept} 個は保持)"
  else
    log "配布: ${home} (管理ファイル更新 ${updated} 個 / 新規作成 ${created} 個 / 個人ファイル保持 ${kept} 個)"
  fi
}

add_to_input_group() {
  local user="$1"
  if id -nG "$user" | tr ' ' '\n' | grep -qx input; then
    log "変更なし: ${user} は既に input グループに入っています"
    return 0
  fi
  usermod -aG input "$user"
  log "追加: ${user} を input グループに入れました (反映には再ログインが必要)"
}

main() {
  require_root

  [ -d "$SKEL" ] || die "/etc/skel がありません。先に他のモジュールを実行してください。"

  local user home shell count=0
  while IFS=$'\t' read -r user home shell; do
    log "対象ユーザー: ${user} (${home})"
    seed_skel_into_home "$user" "$home"
    add_to_input_group "$user"

    case "$shell" in
      /bin/zsh | /usr/bin/zsh) ;;
      *)
        log "  ${user} のログインシェルは ${shell} です。zsh にするには: chsh -s /bin/zsh ${user}"
        ;;
    esac
    count=$((count + 1))
  done < <(list_regular_users)

  if [ "$count" -eq 0 ]; then
    log "対象となる既存ユーザーはいませんでした。"
    return 0
  fi

  log "既存ユーザー ${count} 人に設定を配布しました。"
  log "管理ファイル (.zshrc など) は毎回上書きします。"
  log "個人の設定は次のファイルに書いてください (上書きされません):"
  local p
  for p in "${PERSONAL_FILES[@]}"; do
    log "  ~/${p}"
  done
}

main "$@"
