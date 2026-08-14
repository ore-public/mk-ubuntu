#!/usr/bin/env bash
# Docker Engine (Docker 公式 apt リポジトリ) の検証。
set -uo pipefail
# shellcheck source=harness/asserts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

for p in docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; do
  check "導入済み: ${p}" \
    bash -c "dpkg-query -W -f='\${Status}' '${p}' 2>/dev/null | grep -q '^install ok installed$'"
done

# Ubuntu の docker.io ではなく Docker 公式であること
check "Ubuntu の docker.io を使っていない" \
  bash -c "! dpkg-query -W -f='\${Status}' docker.io 2>/dev/null | grep -q '^install ok installed$'"
check_file /etc/apt/keyrings/docker.gpg
check_file /etc/apt/sources.list.d/docker.sources
check_contains /etc/apt/sources.list.d/docker.sources \
  "^Signed-By: /etc/apt/keyrings/docker.gpg$" \
  "Docker の sources が Signed-By で keyring を参照している"
check_contains /etc/apt/sources.list.d/docker.sources \
  "^URIs: https://download\.docker\.com/linux/ubuntu$" \
  "Docker 公式リポジトリを参照している"

# リポジトリの suite が実行中の Ubuntu のコードネームと一致していること
# shellcheck disable=SC1091
CODENAME="$(. /etc/os-release && printf '%s' "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}")"
check_contains /etc/apt/sources.list.d/docker.sources "^Suites: ${CODENAME}$" \
  "Docker のリポジトリ suite が ${CODENAME} である"

check_cmd_output "docker が起動しバージョンを返す" "Docker version" docker --version
check_cmd_output "docker compose が使える" "Docker Compose version" docker compose version

# サービス
check "docker.service が enabled" \
  bash -c "systemctl is-enabled docker.service | grep -qE 'enabled|static'"
check "docker.service が active" bash -c "systemctl is-active docker.service >/dev/null"

# グループ
check "docker グループが存在する" bash -c "getent group docker >/dev/null"
check_contains /etc/adduser.conf '^EXTRA_GROUPS=.*\bdocker\b' \
  "/etc/adduser.conf の EXTRA_GROUPS に docker がある"
check "既存ユーザーが docker グループに入っている" \
  bash -c "id -nG | tr ' ' '\n' | grep -qx docker"

# 実際にコンテナを動かせること (再ログイン前でも sudo なら確認できる)
if sudo -n true 2>/dev/null; then
  check_cmd_output "コンテナを実行できる" "mk-ubuntu-docker-ok" \
    sudo -n docker run --rm public.ecr.aws/docker/library/busybox:latest \
    echo mk-ubuntu-docker-ok
else
  diag "パスワードなし sudo が使えないため、コンテナ実行の確認をスキップします。"
fi

assert_exit
