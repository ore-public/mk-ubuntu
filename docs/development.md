# 開発者向けドキュメント

このリポジトリを **開発・保守する人** 向けの資料。
セットアップして使うだけなら [README.md](../README.md) を読めばよい。

- VM の初期構築 (人間が 1 回だけ行う): [vm-setup.md](vm-setup.md)
- 検証ハーネスの使い方と手動チェックリスト: [vm-testing.md](vm-testing.md)

---

## リポジトリ構成

```
install.sh              エントリポイント。sudo で実行し、全モジュールを順に適用する
lib/common.sh           全モジュール共通のヘルパー (ログ / 冪等な配置 / apt / dconf)
modules/                機能単位のスクリプト。番号プレフィックスで実行順を制御する
  10-packages.sh          apt の基礎パッケージ
  15-brave.sh             Brave の導入と既定ブラウザ化
  17-desktop-apps.sh      Discord / Zoom / 1Password / Dropbox (公式配布版)
  20-zsh-zimfw.sh         zsh + zimfw
  25-ghostty.sh           Ghostty の設定と既定ターミナル化
  30-xremap.sh            Mac 風キー操作
  40-gnome-workspaces.sh  ワークスペースと Auto Move Windows
  42-gnome-desktop.sh     スクリーンショットとトラックパッドの Mac 化
  45-vicinae.sh           ランチャー Vicinae とクリップボード履歴の拡張
  50-herdr.sh             herdr
  55-docker.sh            Docker Engine (Docker 公式リポジトリ)
  60-agents.sh            Node.js と AI エージェント各種、初回ウィザード
  65-agent-tooling.sh     Playwright MCP、共有ブラウザ、herdr 操作スキル
  70-existing-users.sh    既存ユーザーへの設定配布と input グループ追加
files/                  配置する設定ファイルの原本
  skel/                   /etc/skel に置くもの
  systemd/                /etc/systemd/user に置くもの
  bin/                    /usr/local/bin に置くラッパー
  gnome-extensions/       同梱する GNOME 拡張の zip
  claude-skills/          /etc/skel/.claude/skills/ に置く Claude Code スキル
bin/first-run-wizard    初回ログイン時のエージェント認証ウィザード
harness/                VMware Fusion 検証ハーネス (Mac 側で実行)
  vmtest                  vmrun ラッパー CLI
  asserts/                ゲスト内で実行する状態アサーション (レベル 1)
  e2e/                    実キー入力 E2E テスト (レベル 3、flaky 許容)
tests/                  静的検証と冪等性テスト
docs/                   このファイルと VM 関連の手順書
```

### モジュールの単体実行

```bash
sudo ./install.sh 30-xremap.sh   # モジュール名で指定
sudo ./install.sh 30             # 番号だけでも指定できる
sudo ./install.sh --list         # 一覧を表示
sudo bash modules/30-xremap.sh   # 直接実行もできる
```

### モジュールを追加するときの約束

- `set -euo pipefail` を付ける
- `MODULE_NAME` を設定してから `lib/common.sh` を読み込む
- ファイル配置は `install_file` / `write_file` を使う (内容が同じなら書かない)
- 設定ファイルの書き換えは `set_conf_key` を使う (追記ではなく置換)
- 外部から取るものはモジュール冒頭の変数でバージョンを固定し、SHA256 で検証する
- アーキ分岐は `pick_arch` を使う

`tests/static-checks.sh` がこれらのうち機械的に確認できるものを検査する。

---

## 開発の進め方

```
モジュール実装
  → ./tests/lint.sh          (bash -n + shellcheck を警告ゼロで通す)
  → ./tests/static-checks.sh (リポジトリ構造の静的検証)
  → ./harness/vmtest full    (クリーン VM で通し検証)
  → 失敗のトリアージ (assert ログ / スクリーンショットの読解)
  → リポジトリ修正 → 再実行
```

**コミットの条件**: shellcheck が警告ゼロで通ること、かつ
`vmtest full` のレベル 1 (状態アサーション) が全通過していること。

### 検証

```bash
./tests/lint.sh            # bash -n + shellcheck
./tests/static-checks.sh   # リポジトリ構造とパスの静的検証
./harness/vmtest full      # VM 実機検証 (詳細は vm-testing.md)
```

検証は 3 レベルに分かれる。割り当てと読み方は
[vm-testing.md](vm-testing.md) を参照。

| レベル | 場所 | 判定 |
| --- | --- | --- |
| 1. 状態アサーション | `harness/asserts/` | 自動 (TAP)。終了コードに反映される |
| 2. スクリーンショット | `harness/vmtest shots` | 画像を見て人 (または Claude) が判断 |
| 3. 実キー入力 E2E | `harness/e2e/` | 自動。flaky 許容で終了コードには含めない |

### 冪等性の考え方

- ファイル配置は `install_file` / `write_file` を使う (内容が同じなら書かない)
- 設定ファイルの書き換えは `set_conf_key` を使う (追記ではなく置換なので行が増えない)
- apt は未導入のものだけを対象にする
- 外部バイナリはバージョンを確認し、一致していればダウンロードしない
- `dconf` は生成ファイルの内容が同じなら差分が出ない
- 配列を持つ dconf キー (`enabled-extensions` / `custom-keybindings`) は
  登録簿から和集合をソートして生成するので順序も安定する

冪等性は `tests/state-manifest.sh` が出す状態スナップショットの差分で判定する。
`vmtest full` は `install.sh` を 2 回実行して、この出力に差分がないことを確認する。
スナップショットには既存ユーザーのホームに配った管理ファイルも含まれるので、
「毎回上書きするが結果は同じ」であることも確認できる。

---

## 設計判断

参考情報が古い環境を前提にしている場合でも、**Ubuntu 26.04 の実環境を正**とする。

### Ubuntu 26.04 固有の前提

| 項目 | 26.04 での状況 | 本リポジトリの対応 |
| --- | --- | --- |
| `sudo` | 既定実装が **sudo-rs** | sudo.ws 固有オプションを使わない。`sudo -n` / `sudoers.d` の基本機能のみ |
| coreutils | **rust-coreutils** (`cp`/`mv`/`rm` は GNU のまま) | GNU 固有の非互換フラグを避け、POSIX 準拠の書き方を優先 |
| APT | 3 系。`apt-key` は削除済み | 外部リポジトリは keyring 方式 (`/etc/apt/keyrings/` + `Signed-By`) のみ。deb822 形式で記述 |
| GNOME | 50。Wayland セッションのみ | xremap の GNOME 拡張が必須。X.org 前提の手順は使わない |
| Ghostty | universe に 1.3.0 | `apt install ghostty` で導入。ソースビルドしない |

### 外部 apt リポジトリはベンダー公式のものだけ

原則として外部 apt リポジトリは追加しない。追加するのは
**そのソフトウェアのベンダー自身が運用しているリポジトリ**に限る。
どれも `apt-key` を使わず `/etc/apt/keyrings/` + `Signed-By` の keyring 方式、
deb822 形式で記述する。

| リポジトリ | モジュール | 使う理由 |
| --- | --- | --- |
| Brave | `15-brave.sh` | 個別バージョンの固定 URL が公開されていない |
| 1Password | `17-desktop-apps.sh` | パスワード管理ソフトなので更新が届く経路を優先する |
| Docker | `55-docker.sh` | Ubuntu の `docker.io` ではなく公式版を使うため |

これらは個別バージョンを固定せず、**リポジトリ署名を信頼の根拠**とする。
リポジトリを持たない外部バイナリは、バージョン固定 + SHA256 検証を行う。

### デスクトップアプリは公式配布版のみ。ただし 4 つとも amd64 限定

Discord / Zoom / 1Password / Dropbox は、Ubuntu の apt や snap ではなく
各社の公式配布物を使う。配布形態がばらばらなので扱いも分かれる。

| アプリ | 取得元 | バージョン | 理由 |
| --- | --- | --- | --- |
| Discord | 公式 API の deb | 固定しない | 「最新版」の URL しかなく、かつ古い版だと起動を拒む |
| Zoom | 公式サイトの deb | 固定しない | 同上 |
| Dropbox | 公式サイトの deb | **固定 + SHA256** | バージョン付き URL が公開されている |
| 1Password | 公式 apt リポジトリ | 固定しない | セキュリティ更新を受け取るため |

**1Password の apt リポジトリ定義はパッケージ自身が管理する。**
deb の postinst を読んで確認したところ、導入時に
`/usr/share/keyrings/1password-archive-keyring.gpg` を置き、
`/etc/apt/sources.list.d/1password.sources` を自分の内容で上書きする
(ファイル先頭に「このファイルは 1Password パッケージが管理する。
変更は上書きされる」と書かれる)。

そのため、こちらは **導入前の足場だけ**を用意し、導入が済んだら足場の鍵を片付けて
以後は一切触らない。毎回書き直すと、実行のたびにファイルの内容が
自分の版とパッケージの版で入れ替わり、**冪等でなくなる**。
これは `vmtest amd64` を入れて初めて見つかった (arm64 の VM では
このモジュールごとスキップされるため決して踏めなかった)。

Discord と Zoom は「導入済みなら何もしない」方式にしている。
毎回ダウンロードすると遅く、かつ最新版が変わるたびに再インストールが
走って冪等性が崩れるため。更新はアプリ自身が行う。

**4 つとも公式が amd64 版しか配布していない** (2026-08 時点で確認済み)。

| アプリ | amd64 | arm64 の状況 |
| --- | --- | --- |
| Discord | あり | 配布なし (arch 指定を付けても amd64 の deb が返る) |
| Zoom | あり | 配布なし (CDN の arm64 パスが 403) |
| 1Password | あり | 配布なし (deb が 404) |
| Dropbox | あり | 配布なし (公式の deb 置き場に amd64 しかない) |

そのため `17-desktop-apps.sh` は arm64 では丸ごとスキップする。
`harness/asserts/17-desktop-apps.sh` は arm64 では
「導入されていないこと」と「余計なリポジトリを足していないこと」を確認し、
amd64 では実際の導入結果を確認する。

### amd64 の検証は Docker のエミュレーションで行う

Apple Silicon の VMware Fusion は Apple の Hypervisor を使うため
**ARM ゲストしか動かせない**。x86 のエミュレーション機能はないので、
Fusion で amd64 の検証 VM を作ることはできない。

選択肢を比べた結果、**ゲストの Docker で amd64 コンテナを動かす**方式を採った。

| 方法 | 可否 | 速度 | GUI | 判断 |
| --- | --- | --- | --- | --- |
| VMware Fusion で amd64 VM | 不可 | — | — | Apple Silicon では作れない |
| UTM (QEMU の TCG エミュレーション) | 可 | 非常に遅い | あり | 通し検証には重すぎる |
| **Docker の amd64 エミュレーション** | 可 | 遅いが実用的 | なし | **採用** |
| x86_64 実機 | 可 | 速い | あり | 最終確認として残す |

amd64 でしか確認できないのは `17-desktop-apps.sh` だけで、このモジュールが
行うのは **deb のダウンロードと apt での導入** だけ。systemd も GNOME も
dconf も使わないので、コンテナで検証範囲を十分に覆える。

```bash
./harness/vmtest amd64   # ゲストの Docker で amd64 の ubuntu:26.04 を動かす
```

`vmtest full` からも呼ばれる。中では次を行う。

1. `tonistiigi/binfmt` で amd64 のエミュレーションを登録する (冪等)
2. `--platform linux/amd64` の `ubuntu:26.04` コンテナを起動する
3. コンテナ内で `./install.sh 17-desktop-apps.sh` を適用する
4. 続けて `harness/asserts/17-desktop-apps.sh` を実行し、TAP で結果を出す

コンテナでは確認できないのは「アプリを実際に起動してログインできるか」だけで、
これは元々 [vm-testing.md](vm-testing.md) の手動チェックリストの項目。

### Docker は公式リポジトリ + docker グループ

Ubuntu の `docker.io` ではなく Docker 公式の `docker-ce` を使う。
公式リポジトリは amd64 / arm64 の両方を配布しているのでアーキ分岐は要らない。
リポジトリの suite は `/etc/os-release` のコードネームから決め、
Docker 側にまだ無ければエラーで止める (黙って古い suite を使わない)。

`docker` グループを `/etc/adduser.conf` の `EXTRA_GROUPS` に登録して、
sudo なしで docker を使えるようにしている。

**docker グループはホストの root 権限と同等**である。これは
「開発機なので sudo なしで使えるほうがよい」というトレードオフを
**リポジトリの持ち主に確認したうえで許容した判断**であり、
見落としではない。方針を変える場合は rootless Docker への
切り替えを検討する。README にも権限の意味を明記している。

### 既存ユーザーへのグループ付与は adduser.conf を単一の情報源にする

新規ユーザーには `adduser` が `EXTRA_GROUPS` のグループを付けてくれるが、
既存ユーザーには誰も付けない。かといって
「input は 30-xremap、docker は 55-docker が既存ユーザーに付ける」と
モジュールごとに書くと、追加のたびに書き漏らす。

そこで各モジュールは `add_extra_group` で `/etc/adduser.conf` に登録するだけにし、
`70-existing-users.sh` がその一覧 (`list_extra_groups`) を読んで
既存ユーザーに付与する。グループが増えても 70 側の変更は要らない。

### 既定ブラウザの設定機構: `/etc/xdg/mimeapps.list` + update-alternatives

`xdg-settings set default-web-browser` はユーザー単位にしか効かない。
システム既定にするには、`XDG_CONFIG_DIRS` 上の `/etc/xdg/mimeapps.list` に
`[Default Applications]` を書くのが XDG 仕様どおりの方法で、
ユーザーが `~/.config/mimeapps.list` で後から上書きできる点も都合がよい。
加えて Debian 系ツール向けに `update-alternatives` の `x-www-browser` /
`gnome-www-browser` も Brave に向ける。

`/usr/share/applications/defaults.list` は非推奨なので使わない。

### 既定ターミナルの設定機構: `/etc/xdg/*xdg-terminals.list` + カスタムキーバインド

- Ubuntu 25.04 以降、既定ターミナルは **`xdg-terminal-exec`** が決める。
  参照するファイルは `XDG_CURRENT_DESKTOP` の各要素に対応する
  `<desktop>-xdg-terminals.list` と、最後に `xdg-terminals.list`。
  Ubuntu の `XDG_CURRENT_DESKTOP` は `ubuntu:GNOME` なので、
  `/etc/xdg/` に `ubuntu-xdg-terminals.list` / `gnome-xdg-terminals.list` /
  `xdg-terminals.list` の 3 つを置いて確実に効かせる。
  ユーザーは `~/.config/` 側の同名ファイルで上書きできる。
- **Ctrl+Alt+T はカスタムキーバインドとして登録する。**
  GNOME 50 の `gnome-settings-daemon` の media-keys スキーマからは
  `terminal` キーが削除されており、従来の
  `org.gnome.settings-daemon.plugins.media-keys terminal` は使えない。
  そのため `custom-keybindings/custom0` に
  `binding='<Primary><Alt>t'` / `command='xdg-terminal-exec'` を登録する。
  コマンドを `ghostty` 直書きではなく `xdg-terminal-exec` にすることで、
  既定ターミナルの定義箇所を `xdg-terminals.list` の 1 か所に集約している。
- Ptyxis はアンインストールしない (公式構成からの逸脱を最小化するため)。

### zimfw: 本体はシステム共有、モジュールは skel に事前配置、init.zsh だけ初回生成

3 つの案を比較した。

1. **skel に完全に構築済みの `.zim` を置く** — `init.zsh` は生成時のパスを埋め込むため、
   `/etc/skel` で生成すると各ユーザーのホームで壊れる。不採用。
2. **初回ログイン時に全部インストールする** — 上流が推奨する方式だが、
   初回ログイン時にネットワークが必要になる。オフライン設置や
   ISO 化後の初回起動を考えると不利。
3. **採用: モジュールの実体だけを skel に事前配置し、`init.zsh` は初回起動時に生成**

`zimfw.zsh` 本体は `/usr/local/share/zimfw/zimfw.zsh` に 1 つだけ置く
(更新箇所が 1 か所で済む)。モジュールは `20-zsh-zimfw.sh` が
`/etc/skel/.zim/modules/` に git clone しておく。各ユーザーの初回シェル起動時、
`.zshrc` のブートストラップが `init.zsh` だけを生成する。
モジュールが揃っているのでネットワークは不要。

`init.zsh` と `.zwc` は skel から明示的に削除している。

### `bat` の系統リンク

Ubuntu の `bat` パッケージはコマンド名を `batcat` にする。
要件どおり `.zshrc` に `alias bat="batcat"` を入れているが、
alias はシェル関数なので `bat` という**コマンド名を探すツール**からは見えない。
zimfw の fzf モジュールは Ctrl+T のプレビューに `bat` を使うため、
`/usr/local/bin/bat -> /usr/bin/batcat` の系統リンクも置いている。

同じ理由で、要件の F1 に加えて **ripgrep** を導入している
(zimfw の fzf モジュールはファイル列挙に bfs / fd / ripgrep / ugrep のいずれかを要求する)。

### xremap の GNOME 拡張はリポジトリに同梱する

26.04 は Wayland 専用で、拡張がないとアプリケーション別のリマップが機能しない
(= `application:` の指定が全く効かず、ターミナルの除外も効かない)。必須部品なので、
インストール時のネットワーク状況に左右されないよう
extensions.gnome.org の配布物 (v15、GNOME 45〜50 対応) をリポジトリに同梱している。
チェックサムは `tests/static-checks.sh` が検証する。

### `enabled-extensions` は 1 ファイルで管理する

`org.gnome.shell enabled-extensions` は 1 つのキーに全 UUID を並べる形式なので、
複数モジュールが `/etc/dconf/db/local.d/` に別々に書くとお互いを上書きしてしまう。
また、dconf のシステム既定値を書くと Ubuntu が gschema override で入れている
既定の拡張 (Dock など) も消えてしまう。

そのため `lib/common.sh` の `dconf_enable_extension` が、
実行時の `gsettings get` の値と追加したい UUID の**和集合**を取り、
`/etc/dconf/db/local.d/30-extensions` の 1 ファイルだけに書き込む。
和集合をソートして書くので、何度実行しても結果は同じ。

### 管理ファイルは毎回上書きし、個人設定は別ファイルに分ける

当初は既存ユーザーへの配布を「まだ無いファイルだけコピーする」方式にしていたが、
**それだと一度セットアップした PC にこのリポジトリの更新が二度と届かない**。
`.zshrc` を改善しても、既に `.zshrc` を持っている PC では無視されてしまう。

そこで配布物を管理ファイルと個人ファイルに分けた。

- **管理ファイル**: 毎回そのまま上書きする。更新が確実に行き渡る。
- **個人ファイル** (`*.local`): 無いときだけ作り、以後は触らない。

管理ファイルからは必ず対応する個人ファイルを読み込む。読み込みは末尾で行うので、
個人ファイル側の値が優先される。どの読み込み方も実機で確認した:

- `~/.zshrc` → `source ~/.zshrc.local`
- `~/.zimrc` → `source ~/.zimrc.local` (`zmodule` がそのまま使える)
- `~/.config/ghostty/config` → `config-file = ?config.local`
  (`?` は「ファイルが無くてもエラーにしない」。`?` を付けないと
  Ghostty が起動のたびに Configuration Errors ダイアログを出す)
- `~/.config/xremap/config.yml` → systemd から `xremap-session` ラッパー経由で
  2 つ目の設定ファイルとして渡す。xremap は 2 つ目以降の `modmap` / `keymap` を
  1 つ目にマージする。存在しないファイルを渡すとエラーになるため、
  ラッパーが実在するものだけを並べる

`~/.zim/modules` は git clone した実体であって設定ではないので、
上書き対象からは外し、不足分を補うだけにしている。

`harness/asserts/72-managed-files.sh` が、実際にホームのファイルを書き換えてから
再実行し、管理ファイルが元に戻ること・個人ファイルが残ることを確認する。

### /etc/skel は既存ユーザーには届かないので、別モジュールで配る

`/etc/skel` が効くのは「これから作られるユーザー」だけで、
**install.sh を実行した本人には何も届かない**。実機検証で、xremap の systemd
ユニットが `ConditionPathExists=%h/.config/xremap/config.yml` を満たせず
起動すらしていないことで判明した。

そのため `70-existing-users.sh` が、既存ユーザー (UID 1000-59999) に対して
`/etc/skel` の内容のうち**まだ存在しないファイルだけ**を配る
(`cp -r --update=none`)。対象ユーザー自身として実行するので所有者は自動的に正しくなり、
既存の設定を壊さない。あわせて `input` グループにも追加する
(xremap が入力デバイスを読むのに必要)。

ログインシェルの変更だけは自動で行わず `chsh` の案内にとどめている。
利用者が意図せずシェルを変えられるのを避けるため。

なお、autoinstall ISO や Cubic で使う場合は、利用者アカウントが
インストーラによって後から作られるため `/etc/skel` だけで足りる。
このモジュールは「既に使っている Ubuntu に後から適用する」場合のためのもの。

### アプリと一緒にワークスペースを移動する自作拡張

GNOME 標準の Auto Move Windows は
`window.change_workspace_by_index(n, false)` でウィンドウを移すだけで、
**表示中のワークスペースは切り替えない**。そのためアプリを起動しても
手元の画面は変わらず、「準備ができました」の通知が出るだけになる。

extensions.gnome.org を探しても、これを補う拡張は見当たらなかった。
そこで `files/gnome-extensions/follow-moved-windows@mk-ubuntu/` に
小さな拡張を自作して同梱している。

- Auto Move Windows と**同じ設定** (`application-list`) を読む
- 対象アプリのウィンドウが実際に行き先へ移動していたら
  `Main.activateWindow()` を呼ぶ (ワークスペース切り替えとフォーカスを兼ねる)
- Auto Move Windows の移動が間に合わないことがあるので、
  行き先に着くまで数回だけ確認し直す
- 割当表に載っているアプリだけが対象。他のウィンドウでは画面を動かさない

**これはこのリポジトリで保守する自作コード**である。GNOME の拡張 API は
メジャーバージョンごとに変わるため、GNOME 51 以降へ上げるときは追随が要る。
`40-gnome-workspaces.sh` は metadata.json の対応バージョンが
実行中の GNOME と合わないときに警告を出す。

#### `Meta.Window.activate()` ではワークスペースが切り替わらない

最初は `window.activate(global.get_current_time())` を呼んでいたが、
**画面は切り替わらず「準備ができました」の通知が出るだけ**だった。
イベント由来のタイムスタンプがない状況ではフォーカス奪取の防止に
引っかかるためと考えられる。GNOME Shell 自身が使っている
`Main.activateWindow()` に変えたところ、意図どおり追随するようになった。

これもアサーション (拡張が ACTIVE であること) は通っていて、
スクリーンショットを見て初めて分かった。

#### WM_CLASS を変えても Auto Move Windows からは逃げられない

当初、ターミナルをワークスペース 6 にすると
「Ghostty で開く初回ウィザードも 6 へ飛ばされ、ログイン直後に見えなくなる」
問題を、`ghostty --class=...` で WM_CLASS を分けて回避しようとした。
`--class` が WM_CLASS を変えること自体は実機で確認できたが、
**Auto Move Windows は WM_CLASS ではなくアプリ (desktop ファイル) 単位で
判定する**ため、ウィンドウは Ghostty 扱いのままで効果がなかった。
スクリーンショット (レベル 2) を見て初めて分かった
(`.desktop` の中身を見るアサーションは通ってしまっていた)。

現在は小細工をやめ、上記の自作拡張で画面が追随することによって
ウィザードが見える状態を確保している。

### Alt+Q は Ctrl+Q ではなく Alt+F4 に変換する

GNOME には「アプリ全体を終了する」統一アクションがない。

- `Ctrl+Q` は GTK / GNOME アプリでは「アプリ終了」だが、
  Brave などの Chrome 系は `Ctrl+Q` を割り当てていないため無反応になる。
- `Alt+F4` は GNOME の `close` アクションを発火するので**全アプリで確実に効く**。

Mac の Cmd+Q の「必ず閉じる」体験を優先し、xremap で `Alt-q: Alt-F4` に変換する。
複数ウィンドウを開いているアプリでは手前の 1 窓だけが閉じる点が
macOS とは異なる。ターミナルは除外対象なので効かない。

### スクリーンショットは 4 と 5 が同じ動作になる

macOS の Cmd+Shift+4 は範囲選択、Cmd+Shift+5 は撮影パネルだが、
GNOME には「範囲選択を即開始する」専用アクションがなく、範囲選択も
撮影パネル (`show-screenshot-ui`) の中で行う。そのため
Alt+Shift+4 と Alt+Shift+5 は同じ `show-screenshot-ui` を指す。
Print キーの既定割当は消さずに残している。

### トラックパッド設定は Ubuntu の既定と同じ値

`tap-to-click=true` と `click-method='fingers'` は Ubuntu 26.04 の既定値と
同じだった (実機で確認済み)。それでも dconf に明示しているのは、
上流の既定が変わってもこのディストロの挙動を固定するため。
`tap-and-drag` と `natural-scroll` もあわせて明示している。

### Vicinae は AppImage を展開して置く

Vicinae は amd64 / arm64 とも AppImage でしか配布されていない
(x86_64 のみ tar.gz もあるが、両アーキで同じ手順にするため AppImage を使う)。
AppImage をそのまま実行すると FUSE が必要になるので、
`--appimage-extract` で中身を取り出して `/opt/vicinae` に置き、
`/usr/local/bin/vicinae` からラッパーで呼ぶ。FUSE 不要で起動も速い。

`AppRun` は自分の位置から `APPDIR` を決めるため、シンボリックリンクではなく
ラッパースクリプトで呼んでいる。

AppImage は `libOpenGL.so.0` を同梱していないので、`libopengl0` を
apt で入れている (これがないとサーバーが起動時に落ちる)。

### カスタムキーバインドも 1 ファイルで管理する

`custom-keybindings` は `enabled-extensions` と同じく 1 つのキーに配列を並べる形式で、
モジュールごとに `/etc/dconf/db/local.d/` へ書くとお互いを消してしまう。

そこで `/var/lib/mk-ubuntu/custom-keybindings/` を登録簿とし、
`lib/common.sh` の `dconf_set_custom_keybinding` が呼ばれるたびに
`/etc/dconf/db/local.d/35-custom-keybindings` を作り直す。
`customN` の番号は登録 ID の辞書順で決まるので、何度実行しても同じ結果になる。

現在の登録: `terminal` (Ctrl+Alt+T) と `vicinae` (F12)。

### 画面ロック中は xremap のアプリ別リマップが止まる

GNOME は画面ロック中に拡張をアンロードする。xremap の GNOME 拡張も
止まるため、`application:` 条件を使う `keymap` (Alt+C などの Mac 風バインド) は
ロック中は適用されない。`modmap` の CapsLock → Ctrl はロック中も効く。
ロック解除で拡張は自動的に読み込み直され、元に戻る。

GNOME の仕様であって本リポジトリの不具合ではないが、
検証時にこれを踏むと assert が時間依存で落ちるため、
ハーネスは検証前にロックを解除して自動ロックを止める。

### xremap の systemd ユニット

- パスに `/home/<user>` を書かず `%h` を使う
- **`--watch=device` を付ける。** xremap は既定では起動時に存在した入力デバイスしか
  掴まない。これがないと、ログイン後に挿した USB / Bluetooth キーボードで
  リマップがまったく効かない (VM 検証で、後から作られた仮想デバイスの
  キー入力が 1 件も変換されないことで判明した)
- `After=graphical-session.target` + `ExecStartPre=/usr/bin/sleep 5` で
  GNOME Shell と拡張の起動を待つ
- `Restart=always`
- `/etc/systemd/user/default.target.wants/xremap.service` へのシンボリックリンクで
  システム全体を有効化する (各ユーザーが `systemctl --user enable` しなくてよい)

### Node.js は apt (universe) を使う

Ubuntu 26.04 の universe に `nodejs 22.22.x` がある。Claude Code の要求は
Node.js 22 以上なので、これで足りる。**NodeSource は使わない**
(外部 apt リポジトリの追加を避けるという方針と一致する)。
`60-agents.sh` は導入後にメジャーバージョンを確認し、22 未満なら停止する。

### opencode は Go 製ではなく Bun 製のバイナリ

要件では「Go 製」としていたが、現在の opencode (`anomalyco/opencode`) は
Bun でコンパイルされた単一バイナリを GitHub Releases で配布している。
`opencode-linux-x64.tar.gz` / `opencode-linux-arm64.tar.gz` を
バージョン固定 + SHA256 検証で取得し、`/usr/local/bin/opencode` に置く。

x86_64 では baseline 版ではない通常版を使っている。
古い CPU で起動しない場合は `opencode-linux-x64-baseline.tar.gz` に差し替える。

### Playwright: ブラウザはシステム共有パスに事前配置

`PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers` を
`/etc/environment` (PAM 経由でグラフィカルセッションに効く) と
`/etc/profile.d/mk-ubuntu-playwright.sh` (ログインシェル用) の両方で設定する。

**ディスクサイズへの影響**: arm64 の実測で **982 MB**。
`playwright install chromium` は Chromium 本体だけでなく
Chrome Headless Shell と ffmpeg も入れるため、この容量になる。
ユーザーごとに `~/.cache/ms-playwright` へ落とすと人数分かかるところを 1 回で済ませる。
`playwright install --with-deps chromium` は依存ライブラリの apt 導入も行う。

ブラウザの導入には、グローバル導入した `@playwright/mcp` に同梱されている
playwright CLI を使う。こうすると MCP 本体と**同じバージョン**の
Chromium が入り、バージョン不一致で起動しない事故を避けられる。

### Playwright MCP の登録は first-run-wizard から行う

Claude Code のユーザースコープ設定は `~/.claude.json` にランタイム生成されるため、
`/etc/skel` への静的配置では効かない。したがって
`claude mcp add --scope user` をウィザードから実行する。

登録先は、グローバル導入済みの `playwright-mcp` バイナリを優先する
(実行時にネットワークを必要としないため)。見つからない場合のみ
`npx @playwright/mcp@<固定バージョン>` にフォールバックする。
どちらの場合もバージョンは固定し、`@latest` は使わない。

### herdr 操作スキルは公式のものを採用する

要件では独自に `SKILL.md` を書くとしていたが、**herdr 公式が同等のスキルを提供している**
ことが分かったため、そちらを採用する。

- herdr は v0.8.0 で `herdr --skill` を追加しており、
  **実行中のバイナリに同梱されたスキルを出力する**。
- `65-agent-tooling.sh` はこの出力から `/etc/skel/.claude/skills/herdr-ops/SKILL.md` を生成する。
  これにより「スキルの記述内容」と「`50-herdr.sh` で固定した herdr のバージョン」が
  構造的に必ず一致する (手で同期する必要がない)。
- バイナリから取れない場合に備えて、同じ v0.8.0 の
  `skills/herdr/SKILL.md` を `files/claude-skills/herdr-ops/SKILL.md` に同梱してある。

Claude Code はスキル名をディレクトリ名から決めるため、
配置先ディレクトリ名 (`herdr-ops`) が名前になるよう、
生成時に frontmatter の `name:` 行だけを取り除いている。本文は公式のまま。

### herdr-reviewr のバージョン固定

`herdr plugin install persiyanov/herdr-reviewr --ref v0.30.4` のように
`--ref` でリビジョンを固定する。過去に glibc のバージョン不整合で
バイナリが起動しない問題があったため (現在は musl ビルドで解消)、
ウィザードは導入後に `herdr plugin action list herdr-reviewr` で起動確認を行い、
失敗した場合はログの確認方法を案内する。

### arm64 対応状況

本リポジトリで扱う外部バイナリはすべて arm64 版が提供されている。
**ソースビルドや x86 実機検証送りにした項目はない。**

| 対象 | amd64 | arm64 | 取得元 |
| --- | --- | --- | --- |
| xremap 0.15.10 | `xremap-linux-x86_64-gnome.zip` | `xremap-linux-aarch64-gnome.zip` | GitHub Releases |
| herdr 0.8.0 | `herdr-linux-x86_64` | `herdr-linux-aarch64` | GitHub Releases |
| opencode 1.18.18 | `opencode-linux-x64.tar.gz` | `opencode-linux-arm64.tar.gz` | GitHub Releases |
| Brave | apt (amd64) | apt (arm64) | Brave 公式リポジトリ (分岐不要) |
| Playwright Chromium | あり | あり | `playwright install` がアーキを判別 |
| herdr-reviewr 0.30.4 | あり | あり | `herdr plugin install` が判別 |

`lib/common.sh` の `pick_arch` が `dpkg --print-architecture` の結果で分岐する。
`harness/asserts/05-arch.sh` が、配置されたバイナリの ELF マシン種別が
実行環境と一致していることを検証する。

### keymap はフォーカス中のウィンドウがないと適用されない

`keymap` の `application:` 条件は、フォーカス中のウィンドウの WM_CLASS を
GNOME 拡張から取得して評価する。フォーカス中のウィンドウが 1 つもないと
WM_CLASS が取れず、`not:` を書いていても keymap は適用されない。
`modmap` (CapsLock → Ctrl) はフォーカスに依存せず常に効く。

そのため `harness/e2e/10-key-remap.sh` は、keymap の確認の前に
非ターミナルのウィンドウ (gnome-text-editor など) を開いてフォーカスを作る。

### VM 検証での描画性能について

Ghostty の GPU 描画は **OpenGL 4.3 以上**を必要とする。VMware Fusion のゲストでは
ソフトウェアレンダリングにフォールバックするため、
**VM 上で観測した描画性能は参考値**であり実機の値ではない。
描画品質の確認は [vm-testing.md](vm-testing.md) の手動チェックリストに回している。

---

## バージョン固定の一覧

外部から取得するものはすべて各モジュール冒頭の変数で固定している。

| 対象 | バージョン | 固定箇所 | 検証 |
| --- | --- | --- | --- |
| zimfw | v1.20.0 | `modules/20-zsh-zimfw.sh` | SHA256 |
| xremap | v0.15.10 | `modules/30-xremap.sh` | SHA256 |
| xremap GNOME 拡張 | v15 | リポジトリに同梱 | SHA256 (`tests/static-checks.sh`) |
| Vicinae | v0.25.0 | `modules/45-vicinae.sh` | SHA256 |
| Vicinae GNOME 拡張 | v1.7.0 | リポジトリに同梱 | SHA256 |
| Dropbox | 2026.05.06 | `modules/17-desktop-apps.sh` | SHA256 |
| Discord / Zoom | 固定しない | — | 公式サイトの HTTPS |
| 1Password | 固定しない | — | apt リポジトリ署名 (`Signed-By`) |
| Docker | 固定しない | — | apt リポジトリ署名 (`Signed-By`) |
| herdr | 0.8.0 | `modules/50-herdr.sh` | SHA256 |
| Claude Code | 2.1.231 | `modules/60-agents.sh` | npm のバージョン指定 |
| GitHub Copilot CLI | 1.0.79 | `modules/60-agents.sh` | npm のバージョン指定 |
| opencode | 1.18.18 | `modules/60-agents.sh` | SHA256 |
| Playwright MCP | 0.0.79 | `modules/65-agent-tooling.sh` | npm のバージョン指定 |
| herdr-reviewr | v0.30.4 | `bin/first-run-wizard` | `--ref` によるリビジョン固定 |
| Brave | 固定しない | — | apt リポジトリ署名 (`Signed-By`) |

バージョンを上げるときは、モジュール冒頭の変数と SHA256 を書き換え、
対応する `harness/asserts/` のバージョン確認も合わせて更新する。
