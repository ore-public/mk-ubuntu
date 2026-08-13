#!/usr/bin/env bash
# first-run-wizard の非対話モード (--headless) の検証。
#
# 認証が必要なステップはモックできないため、検証範囲は
# 「登録処理まで到達すること」= Playwright MCP がユーザースコープに登録され、
# herdr のプラグイン導入コマンドが実行されるところまで。
set -uo pipefail
# shellcheck source=harness/asserts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

WIZARD=/usr/local/bin/first-run-wizard
DONE_FLAG="${HOME}/.config/mk-ubuntu/wizard-done"

check "first-run-wizard が実行可能" test -x "$WIZARD"
check "--help が動く" "$WIZARD" --help
check "--status が動く" "$WIZARD" --status

rm -f "$DONE_FLAG"

OUT="$(mktemp)"
if "$WIZARD" --headless >"$OUT" 2>&1; then
  pass "first-run-wizard --headless が正常終了した"
else
  fail "first-run-wizard --headless が異常終了した"
  head -n 40 "$OUT" | while IFS= read -r l; do diag "$l"; done
fi

check "完了フラグが作られた" test -f "$DONE_FLAG"

# 完了フラグがあると再実行しない
check_cmd_output "完了後は再実行しない" "完了済み" "$WIZARD"
check "--force なら完了フラグがあっても動く" "$WIZARD" --force --headless

# Playwright MCP のユーザースコープ登録
check_cmd_output "claude mcp list に playwright がある" "playwright" claude mcp list

# herdr-reviewr。導入されるプラグイン ID はリポジトリ名ではなく persiyanov.reviewr。
if herdr plugin list 2>/dev/null | grep -q "persiyanov.reviewr"; then
  pass "herdr-reviewr が導入されている"
  check_cmd_output "ウィザードが herdr-reviewr の起動確認まで到達している" \
    "herdr-reviewr のバイナリを起動できました" cat "$OUT"
else
  diag "herdr-reviewr は未導入です。ウィザードの出力を確認してください:"
  grep -i "herdr" "$OUT" | head -n 10 | while IFS= read -r l; do diag "$l"; done
  fail "herdr-reviewr が導入されている"
fi

rm -f "$OUT"
assert_exit
