#!/usr/bin/env bash
#
# 冪等性テスト。
# install.sh をもう一度実行しても、管理下の状態に差分が出ないことを確認する。
#
#   sudo ./tests/idempotency.sh
#
# 事前に install.sh が 1 回以上実行されている前提。
# vmtest full はこれと同じ比較を Mac 側で行うので、そちらを使う場合は不要。
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${REPO_ROOT}/tests/state-manifest.sh"

if [ "$(id -u)" -ne 0 ]; then
  printf 'root 権限が必要です: sudo %s\n' "$0" >&2
  exit 1
fi

before="$(mktemp)"
after="$(mktemp)"
diff_out="$(mktemp)"
trap 'rm -f "$before" "$after" "$diff_out"' EXIT

printf '1 回目の状態を記録します\n'
bash "$MANIFEST" >"$before"

printf 'install.sh をもう一度実行します\n'
"${REPO_ROOT}/install.sh" >/dev/null

printf '2 回目の状態を記録します\n'
bash "$MANIFEST" >"$after"

if diff -u "$before" "$after" >"$diff_out"; then
  printf 'ok - install.sh の 2 回目の実行で差分はありません\n'
  exit 0
fi

printf 'not ok - install.sh の 2 回目の実行で差分が出ました\n'
cat "$diff_out"
exit 1
