#!/usr/bin/env bash
#
# 静的検証: 全シェルスクリプトの構文チェックと shellcheck。
# Mac 側でもゲスト内でも実行できる。
#
#   ./tests/lint.sh
#
# 検査に使う shellcheck が PATH になければ、SHELLCHECK 環境変数でパスを渡せる。
#
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELLCHECK="${SHELLCHECK:-shellcheck}"
FAILURES=0

# 検査対象。拡張子のない実行可能スクリプトも含める。
targets() {
  printf '%s\n' \
    "${REPO_ROOT}/install.sh" \
    "${REPO_ROOT}/lib/common.sh" \
    "${REPO_ROOT}/bin/first-run-wizard" \
    "${REPO_ROOT}/harness/vmtest"
  find "${REPO_ROOT}/modules" "${REPO_ROOT}/tests" "${REPO_ROOT}/harness/asserts" \
    "${REPO_ROOT}/harness/e2e" -name '*.sh' -type f 2>/dev/null | sort
}

printf '=== bash -n (構文チェック) ===\n'
while IFS= read -r f; do
  [ -f "$f" ] || continue
  if bash -n "$f"; then
    printf 'ok - %s\n' "${f#"${REPO_ROOT}/"}"
  else
    printf 'not ok - %s\n' "${f#"${REPO_ROOT}/"}"
    FAILURES=$((FAILURES + 1))
  fi
done < <(targets)

printf '\n=== shellcheck ===\n'
if ! command -v "$SHELLCHECK" >/dev/null 2>&1; then
  printf '# shellcheck が見つかりません。導入するか SHELLCHECK にパスを指定してください。\n'
  printf '# 例: SHELLCHECK=/path/to/shellcheck ./tests/lint.sh\n'
  exit "$FAILURES"
fi

while IFS= read -r f; do
  [ -f "$f" ] || continue
  if out="$("$SHELLCHECK" --shell=bash --external-sources --source-path="$REPO_ROOT" "$f" 2>&1)"; then
    printf 'ok - %s\n' "${f#"${REPO_ROOT}/"}"
  else
    printf 'not ok - %s\n' "${f#"${REPO_ROOT}/"}"
    printf '%s\n' "$out"
    FAILURES=$((FAILURES + 1))
  fi
done < <(targets)

printf '\n失敗数: %d\n' "$FAILURES"
exit "$FAILURES"
