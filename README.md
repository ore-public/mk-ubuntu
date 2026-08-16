# mk-ubuntu

素の **Ubuntu 26.04 LTS Desktop** を 1 コマンドで
「Mac っぽく操作でき、AI エージェント開発環境が整った状態」にします。

```bash
git clone <このリポジトリ> && cd mk-ubuntu
sudo ./install.sh
```

実行後に再起動すれば、そのまま使い始められます。
何度実行しても安全です (2 回目以降は変更がなければ何も起きません)。

---

## 何が変わるか

| | |
| --- | --- |
| **キー操作** | CapsLock が Ctrl に。Alt+C / Alt+V などが Mac の Command 相当に |
| **ランチャー** | **F12** で Vicinae (Spotlight / Alfred 相当)。クリップボード履歴つき |
| **ワークスペース** | 10 個固定。Ctrl+1 〜 Ctrl+0 で移動 |
| **ターミナル** | Ghostty が既定に。Ctrl+Alt+T で開く |
| **シェル** | zsh + zimfw。Ctrl+R で履歴検索、Ctrl+T でファイル検索 |
| **ブラウザ** | Brave が既定に (Firefox も残ります) |
| **プレビュー** | Files でスペースキーを押すとプレビュー (Quick Look 相当) |
| **AI エージェント** | Claude Code / GitHub Copilot CLI / opencode / herdr |
| **アプリ** | Discord / Zoom / 1Password / Dropbox (公式配布版) |
| **コンテナ** | Docker Engine と Docker Compose (Docker 公式版) |
| **言語バージョン管理** | mise (Ruby / Node.js / PHP などをプロジェクト単位で切替) |

---

## 動作環境

| 項目 | 対応 |
| --- | --- |
| OS | **Ubuntu 26.04 LTS Desktop のみ** |
| デスクトップ | GNOME (Wayland セッション) |
| アーキテクチャ | amd64 / arm64 の両方 |

他のバージョンの Ubuntu では動作を確認していません。実行すると警告が出ます。

> このリポジトリが行うのは「既にある Ubuntu のセットアップ」までです。
> インストール ISO の作成は含みません。

---

## セットアップ手順

### 1. 実行する

```bash
sudo ./install.sh
```

10 〜 20 分ほどかかります (ブラウザやエージェントをダウンロードするため)。
ディスクは 3 GB ほど使います。内訳の大きいものは次のとおりです。

| 用途 | サイズ |
| --- | --- |
| Playwright の Chromium (全ユーザー共有) | 約 1.0 GB |
| AI エージェント各種 (npm) | 約 1.3 GB |
| Brave | 約 440 MB |
| Vicinae | 約 230 MB |

### 2. 再起動する

キーリマップ・ワークスペース設定・ランチャーは、
**ログインし直さないと反映されません。**

### 3. 初回ログイン時のウィザードに答える

再起動後の最初のログインで、セットアップウィザードが自動で開きます。
次の順に案内するので、使うものだけ設定してください。

1. Claude Code のログイン
2. GitHub のログインと Copilot CLI のセットアップ
3. opencode の認証
4. herdr と Claude Code の連携
5. Claude Code からブラウザを操作するための設定 (Playwright)

- 使わないものは **`s`** でスキップできます
- 途中でやめたいときは **`q`**。あとで続きからやり直せます
- やり直したいときは、ターミナルで `first-run-wizard --force`
- 一度完了すると、次のログインからは自動で開きません

> **パスワードや API キーはこのリポジトリに一切含まれていません。**
> 認証はすべて各ツール自身のログイン画面で行われます。

### 4. zsh に切り替える (既にあるアカウントを使っている場合)

`install.sh` は、今あるアカウントのログインシェルを勝手に変えません。
zsh を使うには自分で切り替えて、ログアウトしてください。

```bash
chsh -s /bin/zsh
```

設定ファイルはすでに配置済みなので、切り替えるだけで使えます。
**このあと新しく作るユーザーは、最初から zsh になります。**

---

## 自分好みに設定を変える

### 大原則: 自分の設定は `.local` の付いたファイルに書く

このリポジトリが配る設定ファイルは 2 種類あります。

| | ファイル | 扱い |
| --- | --- | --- |
| **触らないファイル** | `~/.zshrc`<br>`~/.zimrc`<br>`~/.config/ghostty/config`<br>`~/.config/xremap/config.yml` | `install.sh` を実行するたびに**上書きされます** |
| **自分用のファイル** | `~/.zshrc.local`<br>`~/.zimrc.local`<br>`~/.config/ghostty/config.local`<br>`~/.config/xremap/config.local.yml` | **一度作られたら二度と書き換えられません** |

**自分の設定は必ず `.local` の付いたファイルに書いてください。**
上の段のファイルを直接編集しても、次回の `install.sh` で消えます。

こうなっているのは、**このリポジトリが更新されたときに、
使用中の PC で `install.sh` を実行し直すだけで最新の設定が反映されるようにするため**です。

`.local` ファイルは自動的に読み込まれ、しかも**あとから読まれる**ので、
元の設定を上書きできます。

```bash
# 例: エイリアスを足す
echo 'alias ll="ls -la"' >> ~/.zshrc.local

# 例: ターミナルのフォントを大きくする
echo 'font-size = 15' >> ~/.config/ghostty/config.local

# 例: キーリマップを足す (反映するには下のコマンドが必要)
$EDITOR ~/.config/xremap/config.local.yml
systemctl --user restart xremap.service
```

### 更新を取り込む

```bash
git pull
sudo ./install.sh
```

`.local` ファイルに書いた設定はそのまま残ります。

### ランチャーの呼び出しキーを変える

初期設定は **F12** です。

- **自分だけ変える**: 「設定 → キーボード → キーボードショートカット →
  カスタムショートカット」に **Vicinae** があるので、そこで変更
- **全ユーザーで変える**: `/etc/dconf/db/local.d/35-custom-keybindings` の
  Vicinae の `binding=` を書き換えて `sudo dconf update`

> F12 はブラウザの開発者ツールのキーでもあります。
> Vicinae に割り当てている間は、開発者ツールは Ctrl+Shift+I で開いてください。
> 気になる場合は上の方法でキーを変えられます。

### アプリごとの起動ワークスペースを変える

初期設定は「Brave が 1 / Ghostty が 6 / Zoom が 8 / Discord が 9」です。

- **自分だけ変える**: 「拡張機能」アプリの **Auto Move Windows** の設定から変更
- **全ユーザーで変える**: `/etc/dconf/db/local.d/40-workspaces` の
  `application-list` を編集して `sudo dconf update`

```
application-list=['brave-browser.desktop:1', 'com.mitchellh.ghostty.desktop:6', 'Zoom.desktop:8', 'discord.desktop:9', 'code.desktop:3']
```

書式は `'<desktop ファイル名>:<ワークスペース番号>'` です。

---

## 使い方

### キー操作 (Mac 風)

| キー | 動作 |
| --- | --- |
| CapsLock | Ctrl として働く |
| Alt+C / Alt+V / Alt+X | コピー / ペースト / カット |
| Alt+Z / Alt+A / Alt+S | 元に戻す / 全選択 / 保存 |
| Alt+F / Alt+T / Alt+W | 検索 / 新規タブ / タブを閉じる |
| Alt+Q | ウィンドウを閉じる |
| Ctrl+P / Ctrl+N / Ctrl+B / Ctrl+F | カーソルを上 / 下 / 左 / 右へ |
| Ctrl+A / Ctrl+E | 行頭 / 行末へ |
| Ctrl+H / Ctrl+D / Ctrl+K | 前を削除 / 後ろを削除 / 行末まで削除 |
| Alt+Shift+3 | 画面全体のスクリーンショット |
| Alt+Shift+4 / Alt+Shift+5 | スクリーンショットのパネルを開く |
| Ctrl+1 〜 Ctrl+0 | ワークスペース 1 〜 10 へ移動 |
| Ctrl+Shift+1 〜 Ctrl+Shift+0 | ウィンドウをワークスペースへ移動 |
| Ctrl+Alt+T | ターミナル (Ghostty) を開く |
| F12 | ランチャー (Vicinae) を開く |

**ターミナルの中だけは Alt+C / Alt+V の扱いが別です。**
ターミナル内では Ghostty 自身の機能でコピー / ペーストになります。
これは Ctrl+C の「中断」を壊さないための意図的な仕様です。

トラックパッドは、タップでクリック・2 本指のタップで右クリック・
ナチュラルスクロールになります。

### ランチャー (Vicinae)

**F12** で開きます。アプリの起動、ファイル検索、計算、
**クリップボード履歴**などが 1 か所からできます。

クリップボード履歴は「Clipboard History」から見られます。
コピーした内容が自動で記録されていきます。

### シェル

- **Ctrl+R** — コマンド履歴をあいまい検索
- **Ctrl+T** — ファイルを検索 (右側にプレビューが出ます)
- 入力中にグレーで候補が出ます (右矢印キーで確定)
- コマンドの色分け表示
- `bat` でファイルを色付き表示できます

### 言語バージョンの切り替え (mise)

Ruby / Node.js / PHP などをプロジェクトごとに切り替えられます。

```bash
mise use -g ruby@3.4       # 全体で使う Ruby を決める
mise use ruby@3.4          # このディレクトリだけ (mise.toml が作られる)
mise use node@22 php@8.4   # 他の言語も同じ書き方
mise ls                    # 入っているものを見る
```

Ruby はビルド済みバイナリがあればそれを使い、無ければソースからビルドします。
PHP は必ずソースからビルドします (Composer も一緒に入ります)。
**Ruby / PHP / Node.js のビルドに必要な apt パッケージは導入済み**なので、
追加のインストールなしにそのまま使えます。

> PHP 8.1 以上のビルドを実機で確認しています (8.1.34 で約 3 分)。
> それより古い PHP は現代の OpenSSL や gcc に対応しておらず、ビルドできません。
> 古い PHP が必要なときは Docker の公式イメージを使ってください。

> **バージョンを指定していないディレクトリでは、システムのコマンドがそのまま使われます。**
> mise は `mise.toml` や `.tool-versions` で指定したものだけを差し替えます。

> **注意:** AI エージェント (`claude` など) はシステムの Node.js で動いています。
> mise であるプロジェクトに古い Node.js を指定すると、そのディレクトリでは
> エージェントが動かなくなることがあります。その場合はプロジェクトの
> Node.js を 22 以上にするか、別のディレクトリでエージェントを起動してください。

### AI エージェント

ターミナルから次のコマンドが使えます。

| コマンド | 内容 |
| --- | --- |
| `claude` | Claude Code |
| `copilot` | GitHub Copilot CLI |
| `opencode` | opencode |
| `herdr` | エージェント向けターミナル多重化ツール |

Claude Code からは、ブラウザ操作 (Playwright) と herdr の操作ができます。

---

## 導入されるもの

apt から入るもののほか、次を特定のバージョンで導入します。

| ソフトウェア | バージョン |
| --- | --- |
| Ghostty (ターミナル) | Ubuntu の 1.3.0 |
| Docker Engine / Compose | 最新 (Docker 公式リポジトリ) |
| 1Password | 最新 (1Password 公式リポジトリ) |
| Discord / Zoom | 最新 (公式サイト。アプリが自身で更新します) |
| Dropbox | 2026.05.06 |
| Brave (ブラウザ) | 最新 (公式リポジトリ) |
| Vicinae (ランチャー) | v0.25.0 |
| xremap (キーリマップ) | v0.15.10 |
| zimfw (zsh の設定フレームワーク) | v1.20.0 |
| herdr | 0.8.0 |
| Claude Code | 2.1.231 |
| GitHub Copilot CLI | 1.0.79 |
| opencode | 1.18.18 |
| Node.js (システム) | Ubuntu の 22 系 |
| mise (言語バージョン管理) | v2026.8.6 |

ダウンロードするものは、バージョンを固定できるものはチェックサムを検証し、
「最新版」しか配布されていないものは公式サイトの HTTPS と
apt リポジトリの署名を信頼の根拠にしています。

> **Discord / Zoom / 1Password / Dropbox は、公式が amd64 版しか配布していません。**
> arm64 (Apple Silicon の VM や ARM 機) では、この 4 つだけ導入がスキップされます。
> Docker を含め、他の機能はすべて arm64 でも動きます。

> **Docker を sudo なしで使えるようにするため、`docker` グループに追加します。**
> このグループに入るとホストの root 権限と同等の操作ができる点にご留意ください。
> 反映には再ログインが必要です。

Playwright の Chromium は全ユーザー共有で `/opt/playwright-browsers` に置きます。
ユーザーごとに重複してダウンロードされません。

---

## 困ったとき

**キーリマップが効かない**

再起動 (またはログアウトとログイン) をしましたか。
それでも効かない場合:

```bash
systemctl --user status xremap.service
```

**F12 を押してもランチャーが出ない**

```bash
systemctl --user status vicinae.service
```

**docker コマンドで permission denied が出る**

`docker` グループの追加はログインし直すまで反映されません。
一度ログアウトしてください。

```bash
id -nG | tr ' ' '\n' | grep docker   # 反映されていれば docker と出る
```

**Discord / Zoom / 1Password / Dropbox が入っていない**

お使いのマシンが arm64 ではありませんか。
この 4 つは公式が amd64 版しか配布していないため、arm64 では導入されません。

```bash
dpkg --print-architecture   # amd64 と出るか確認
```

**ターミナルが zsh にならない**

`chsh -s /bin/zsh` を実行してログアウトしてください
(既にあるアカウントのシェルは自動では変わりません)。

**設定を変えたのに戻ってしまう**

`.local` の付かないファイルを編集していませんか。
上の「[自分好みに設定を変える](#自分好みに設定を変える)」を参照してください。

**セットアップウィザードをもう一度実行したい**

```bash
first-run-wizard --force
```

**一部だけやり直したい**

```bash
sudo ./install.sh --list        # 何があるか見る
sudo ./install.sh 45-vicinae.sh # 指定したものだけ実行
```

---

## ライセンスの注意

このリポジトリのスクリプトと設定ファイルは、リポジトリのライセンス表記に従います。

導入される第三者ソフトウェアには個別のライセンスがあります。特に:

- **herdr は AGPL-3.0 / 商用のデュアルライセンス**です。
  セットアップ済みのイメージや ISO を**外部に配布する場合は条件の確認が必要**です。
- Brave、Claude Code、GitHub Copilot CLI は、それぞれの利用規約に従ってください。
- xremap は MIT、同梱している GNOME 拡張は GPLv2+ です。

---

## 開発者の方へ

このリポジトリの構成・設計判断・検証方法は
[docs/development.md](docs/development.md) にまとめてあります。

- [docs/development.md](docs/development.md) — 構成、設計判断、開発の進め方
- [docs/vm-setup.md](docs/vm-setup.md) — 検証用 VM の作り方
- [docs/vm-testing.md](docs/vm-testing.md) — 検証ハーネスの使い方と手動チェックリスト
