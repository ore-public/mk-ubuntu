# 検証用 VM の初期構築手順

VMware Fusion 上に、ハーネス (`harness/vmtest`) が使うクリーン VM を作る手順。
**この作業は人間が 1 回だけ行う。** 以後はスナップショット `clean` への復元で
毎回同じ初期状態からやり直せる。

前提: Apple Silicon Mac (M3) + VMware Fusion。ゲストは **arm64 版 Ubuntu 26.04 LTS Desktop**。

---

## 1. ISO を用意する

Ubuntu 26.04 LTS (Resolute Raccoon) Desktop の **arm64** ISO を取得する。

    https://cdimage.ubuntu.com/releases/26.04/release/

amd64 版ではハーネスが動かない (Apple Silicon の Fusion は arm64 ゲストのみ)。
x86_64 固有の確認は後日、実機で行う。

## 2. VM を作る

Fusion で新規 VM を作成し、次の設定にする。

| 項目 | 値 | 理由 |
| --- | --- | --- |
| メモリ | 8 GB 以上 | GNOME + Playwright の Chromium が動く |
| CPU | 4 コア以上 | プロビジョンの待ち時間を短くする |
| ディスク | 60 GB 以上 | Playwright のブラウザで数 GB 使う |
| ネットワーク | 共有 (NAT) | `vmrun getGuestIPAddress` で IP が取れる |
| アクセラレーション | 3D グラフィックスを有効化 | Ghostty の描画確認のため |

## 3. Ubuntu をクリーンインストールする

インストーラの選択は次のとおり。**検証対象を汚さないため、追加ソフトは入れない。**

- インストール種別: 通常のインストール
- サードパーティ製ソフトウェア: 任意 (どちらでもよい)
- ユーザー作成: ユーザー名は `harness/config.env` の `GUEST_USER` と揃える (例: `ubuntu`)
- 自動ログイン: **有効にする** (グラフィカルセッション前提の検証に必要)

インストール後、再起動して初回セットアップを完了させる。

## 4. 検証に必要な最小限のものだけ仕込む

ゲスト内で次を実行する。ここで入れるのは
**open-vm-tools / openssh-server / ydotool** の 3 つだけ。

```bash
sudo apt update
sudo apt install -y open-vm-tools open-vm-tools-desktop openssh-server ydotool
sudo systemctl enable --now ssh
```

- `open-vm-tools` — `vmrun getGuestIPAddress` と `captureScreen` に必要
- `openssh-server` — ハーネスはゲスト内実行に `runProgramInGuest` ではなく SSH を使う
- `ydotool` — レベル 3 の実キー入力 E2E テスト (`harness/e2e/`) に必要

## 5. 自動ログインを確認する

手順 3 で有効にしていない場合は、ここで設定する。

```bash
sudo sed -i 's/^#\?  *AutomaticLoginEnable *=.*/AutomaticLoginEnable=true/' /etc/gdm3/custom.conf
sudo sed -i "s/^#\?  *AutomaticLogin *=.*/AutomaticLogin=$USER/" /etc/gdm3/custom.conf
```

`/etc/gdm3/custom.conf` の `[daemon]` セクションが次のようになっていればよい。

```ini
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=ubuntu
```

## 6. Mac の SSH 公開鍵を登録する

Mac 側で鍵がなければ作る。

```bash
ssh-keygen -t ed25519 -C "mk-ubuntu harness"
```

ゲストへ登録する (ゲストの IP は `ip -4 addr` で確認)。

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub ubuntu@<ゲストのIP>
```

## 7. パスワードなし sudo を許可する

ハーネスは `sudo ./install.sh` を非対話で実行する。
また、新規ユーザー作成テスト (`harness/asserts/70-new-user.sh`) も
パスワードなし sudo を必要とする。

```bash
echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/90-harness
sudo chmod 0440 /etc/sudoers.d/90-harness
```

> Ubuntu 26.04 の `sudo` の既定実装は **sudo-rs**。上の書式は sudo-rs でも有効。
> 設定を反映できたかは `sudo -n true` が成功するかで確認する。

パスワードなし sudo を許可したくない場合は、代わりに
`harness/config.env` の `GUEST_SUDO_PASSWORD` にパスワードを設定する。
ただしその場合、新規ユーザー作成テストは失敗する。

## 8. 動作確認

Mac 側から次が通ることを確認する。

```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@<ゲストのIP> 'sudo -n true && echo OK'
```

## 9. スナップショット `clean` を作る

**ゲストをシャットダウンしてから** Fusion のメニューで
「仮想マシン」→「スナップショット」→「スナップショットを撮る」を選び、
名前を **`clean`** にする。

コマンドラインでも作れる。

```bash
VMRUN="/Applications/VMware Fusion.app/Contents/Public/vmrun"
"$VMRUN" -T fusion snapshot "<VMのパス>.vmx" clean
```

ハーネスは毎回このスナップショットへ復元してから始める。

## 10. ハーネスの設定を書く

Mac 側で行う。

```bash
cp harness/config.env.example harness/config.env
$EDITOR harness/config.env
```

`VMX` に .vmx のフルパス、`GUEST_USER` にゲストのユーザー名を書く。
`harness/config.env` は `.gitignore` 済みなのでリポジトリには入らない。

設定できたら通しで動かす。

```bash
./harness/vmtest full
```

---

## VM 検証での注意点

- **Ghostty の描画性能は参考値**。Ghostty の GPU 描画は OpenGL 4.3 以上を必要とし、
  VMware Fusion のゲストではソフトウェアレンダリングにフォールバックする。
  VM 上でのスクロールの滑らかさや起動速度は実機の性能を表さない。
- **26.04 の GNOME は Wayland セッションのみ**。X.org セッションは存在しないので、
  ログイン画面でセッションを選ぶ必要はない。
- `vmrun getGuestIPAddress -wait` が返らない場合は、ゲストで `open-vm-tools` が
  動いているか (`systemctl status open-vm-tools`) を確認する。
- **`vmtest shot` にはゲストのログインパスワードが必要**。
  `vmrun captureScreen` がゲストへのログインを要求するため、
  `harness/config.env` の `GUEST_PASSWORD` を設定する。
  未設定でも `vmtest full` はレベル 1 まで完走する。
- **自動ログインの副作用でログインキーリングが解錠されない。**
  そのため Brave などキーリングを使うアプリを起動すると
  「Authentication required」のダイアログが画面を覆う。これは検証 VM が
  自動ログインだから起きることで、パスワードを入力して通常どおりログインする
  実機では起きない。`vmtest shots` は Brave を `--password-store=basic` で
  起動してこれを避けている。
- **画面ロック中は GNOME が拡張をアンロードする。** xremap の GNOME 拡張も
  止まるため、放置してロックがかかった VM に対して `vmtest assert` を実行すると
  アプリ別リマップの検証が落ちる。ハーネスは検証前にロックを解除し、
  自動ロックを止める (`prepare_guest_session`)。
