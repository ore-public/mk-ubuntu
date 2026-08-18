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
# あわせて、各モジュールが /etc/adduser.conf の EXTRA_GROUPS に登録した
# グループ (input / docker など) を既存ユーザーにも付与する。
# 新規ユーザーは adduser が付けてくれるが、既存ユーザーには誰も付けないため。
#
# GNOME 拡張の有効化も同じ事情がある。dconf のシステム既定値は
# 「ユーザー個人の設定が無いとき」しか効かず、enabled-extensions は
# 1 つのキーに配列を持つ形式なので、個人の値があるとシステム既定は
# 丸ごと無視される。Ubuntu を普通に使っていると個人の値が入っていることが
# あるため、既存ユーザーには個人の設定にも足しておく。
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

# システム既定として有効化した GNOME 拡張の UUID を 1 行ずつ出力する。
# 定義元は lib/common.sh が作る 30-extensions なので、そこから読む。
list_system_extensions() {
  local file="${DCONF_DB_DIR}/30-extensions"
  [ -f "$file" ] || return 0
  grep -m1 '^enabled-extensions=' "$file" 2>/dev/null |
    grep -oE "'[^']+'" | tr -d "'" || true
}

# 対象ユーザーとして dconf を実行する。
# ログイン中ならそのセッションのバスを使い、居なければ一時的なバスを作る
# (どちらの場合も書き込み先は ~/.config/dconf/user なので結果は同じ)。
run_user_dconf() {
  local user="$1" uid
  shift
  uid="$(id -u "$user")"

  if [ -S "/run/user/${uid}/bus" ]; then
    runuser -u "$user" -- env \
      "XDG_RUNTIME_DIR=/run/user/${uid}" \
      "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${uid}/bus" \
      "$@"
  else
    runuser -u "$user" -- env "XDG_RUNTIME_DIR=/run/user/${uid}" \
      dbus-run-session -- "$@"
  fi
}

# 既存ユーザーの個人設定にも拡張を足す。既にあるものは触らない。
enable_extensions_for_user() {
  local user="$1" current new uuids=() u
  local merge_script="${REPO_ROOT}/lib/merge-extensions.py"

  while IFS= read -r u; do
    [ -n "$u" ] && uuids+=("$u")
  done < <(list_system_extensions)

  [ "${#uuids[@]}" -gt 0 ] || return 0

  # 個人の値が無ければシステム既定がそのまま効くので触らない
  current="$(run_user_dconf "$user" dconf read /org/gnome/shell/enabled-extensions 2>/dev/null || true)"
  if [ -z "$current" ]; then
    log "変更なし: ${user} の拡張 (システム既定が効きます)"
    return 0
  fi

  new="$(python3 "$merge_script" "$current" "${uuids[@]}")"

  if [ "$new" = "$current" ]; then
    log "変更なし: ${user} の拡張 (個人設定に登録済み)"
    return 0
  fi

  if run_user_dconf "$user" dconf write /org/gnome/shell/enabled-extensions "$new" 2>/dev/null; then
    log "追加: ${user} の個人設定に GNOME 拡張を登録しました"
    log "  反映にはログインし直しが必要です"
  else
    warn "${user} の個人設定に拡張を登録できませんでした。"
    warn "  本人が次を実行してください: gnome-extensions enable <UUID>"
  fi
}

# /etc/adduser.conf の EXTRA_GROUPS に並んでいるグループを既存ユーザーに付与する。
# 何をどのグループに入れるかは各モジュールが登録するので、ここは中身を知らない。
add_registered_groups() {
  local user="$1" group added=0
  while IFS= read -r group; do
    [ -n "$group" ] || continue
    if ! getent group "$group" >/dev/null 2>&1; then
      warn "グループ ${group} が存在しないため ${user} には付与しません。"
      continue
    fi
    if id -nG "$user" | tr ' ' '\n' | grep -qx "$group"; then
      continue
    fi
    usermod -aG "$group" "$user"
    log "追加: ${user} を ${group} グループに入れました"
    added=$((added + 1))
  done < <(list_extra_groups)

  if [ "$added" -eq 0 ]; then
    log "変更なし: ${user} のグループ"
  else
    log "  グループの変更は再ログインで反映されます"
  fi
}

main() {
  require_root

  [ -d "$SKEL" ] || die "/etc/skel がありません。先に他のモジュールを実行してください。"

  local user home shell count=0
  while IFS=$'\t' read -r user home shell; do
    log "対象ユーザー: ${user} (${home})"
    seed_skel_into_home "$user" "$home"
    add_registered_groups "$user"
    enable_extensions_for_user "$user"

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
