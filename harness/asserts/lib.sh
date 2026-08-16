#!/usr/bin/env bash
# ゲスト内で実行する検証スクリプトの共通ヘルパー。
# 各チェックは「ok - 説明」「not ok - 説明」の 1 行を出す。
# 通し番号と 1..N のプランは Mac 側の vmtest が付ける。

# 直近のチェックが失敗したかどうか
ASSERT_FAILED=0

pass() { printf 'ok - %s\n' "$1"; }

fail() {
  printf 'not ok - %s\n' "$1"
  ASSERT_FAILED=1
}

diag() { printf '#   %s\n' "$*"; }

# check <説明> <コマンド...>
# コマンドの終了コードで合否を決める。失敗時は出力を診断行として出す。
check() {
  local desc="$1"
  shift
  local out rc=0
  out="$("$@" 2>&1)" || rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "$desc"
  else
    fail "$desc"
    diag "終了コード: ${rc}"
    [ -n "$out" ] && printf '%s\n' "$out" | while IFS= read -r l; do diag "$l"; done
  fi
  return 0
}

# check_file <パス> [説明]
check_file() {
  local path="$1" desc="${2:-ファイルが存在する: $1}"
  check "$desc" test -f "$path"
}

# check_dir <パス> [説明]
check_dir() {
  local path="$1" desc="${2:-ディレクトリが存在する: $1}"
  check "$desc" test -d "$path"
}

# check_contains <パス> <正規表現> [説明]
check_contains() {
  local path="$1" pattern="$2"
  local desc="${3:-${path} に ${pattern} を含む}"
  if [ ! -f "$path" ]; then
    fail "$desc"
    diag "ファイルがありません: ${path}"
    return 0
  fi
  check "$desc" grep -qE "$pattern" "$path"
}

# check_cmd_output <説明> <期待する正規表現> <コマンド...>
check_cmd_output() {
  local desc="$1" pattern="$2"
  shift 2
  local out rc=0
  out="$("$@" 2>&1)" || rc=$?
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qE "$pattern"; then
    pass "$desc"
  else
    fail "$desc"
    diag "終了コード: ${rc} / 期待: ${pattern}"
    printf '%s\n' "$out" | head -n 10 | while IFS= read -r l; do diag "$l"; done
  fi
  return 0
}

# check_extension_supports_current_shell <metadata.json のパス> <拡張の名前>
# 実行中の GNOME Shell のメジャーバージョンを metadata.json が宣言しているか見る。
# バージョンを直書きすると、GNOME が上がったときに古いままでも素通りしてしまう。
# ここが落ちることが「拡張を新しい GNOME に追随させる」合図になる。
check_extension_supports_current_shell() {
  local metadata="$1" label="$2" major
  major="$(gnome-shell --version 2>/dev/null | grep -oE '[0-9]+' | head -n 1)"

  if [ -z "$major" ]; then
    diag "gnome-shell のバージョンを取得できないため、${label} の対応確認をスキップします。"
    return 0
  fi

  if [ ! -f "$metadata" ]; then
    fail "${label}が GNOME ${major} に対応している"
    diag "metadata.json がありません: ${metadata}"
    return 0
  fi

  if grep -q "\"${major}\"" "$metadata"; then
    pass "${label}が GNOME ${major} に対応している"
  else
    fail "${label}が GNOME ${major} に対応している"
    diag "metadata.json の shell-version に ${major} がありません。"
    diag "GNOME の更新に追随して拡張を差し替える必要があります。"
  fi
}

# 各スクリプトの末尾で呼ぶ
assert_exit() { exit "$ASSERT_FAILED"; }
