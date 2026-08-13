# mk-ubuntu

素の **Ubuntu 26.04 LTS (Resolute Raccoon) Desktop** を、1 コマンドで
「インストール直後から Mac っぽく操作でき、AI エージェント開発環境が整っている状態」
にするプロビジョニングリポジトリ。

自作ディストリビューションの第一段階にあたる。ここで作った成果物は、
後段の autoinstall ISO や Cubic リマスターにそのままペイロードとして載せる。
**ISO のビルドはこのリポジトリのスコープ外。**

```bash
git clone <このリポジトリ> && cd mk-ubuntu
sudo ./install.sh
```

何度実行しても安全 (冪等)。2 回目は差分なしで正常終了する。

---

## ターゲット

| 項目 | 値 |
| --- | --- |
| OS | Ubuntu 26.04 LTS Desktop のみ |
| デスクトップ | GNOME 50 / **Wayland セッションのみ** (26.04 に X.org セッションはない) |
| アーキテクチャ | amd64 / arm64 の両対応 |
| シェル | zsh (+ zimfw) |
| ターミナル | Ghostty (Ptyxis も残す) |
| ブラウザ | Brave (既定)。Firefox も残す |

開発マシンは Apple Silicon Mac (M3)。動作検証は VMware Fusion 上の
**arm64 版 Ubuntu 26.04** で行う。x86_64 固有の確認は後日実機で行う。

新規ユーザーを作ると全設定が自動で継承される (`/etc/skel` + システム既定値で構成)。

---

## リポジトリ構成

```
install.sh              エントリポイント。sudo で実行し、全モジュールを順に適用する
lib/common.sh           全モジュール共通のヘルパー (ログ / 冪等な配置 / apt / dconf)
modules/                機能単位のスクリプト。番号プレフィックスで実行順を制御する
  10-packages.sh          apt の基礎パッケージ
  15-brave.sh             Brave の導入と既定ブラウザ化
  20-zsh-zimfw.sh         zsh + zimfw
  25-ghostty.sh           Ghostty の設定と既定ターミナル化
  30-xremap.sh            Mac 風キー操作
  40-gnome-workspaces.sh  ワークスペースと Auto Move Windows
  50-herdr.sh             herdr
  60-agents.sh            Node.js と AI エージェント各種、初回ウィザード
  65-agent-tooling.sh     Playwright MCP、共有ブラウザ、herdr 操作スキル
files/                  配置する設定ファイルの原本
  skel/                   /etc/skel に置くもの
  systemd/                /etc/systemd/user に置くもの
  gnome-extensions/       同梱する GNOME 拡張の zip
  claude-skills/          /etc/skel/.claude/skills/ に置く Claude Code スキル
bin/first-run-wizard    初回ログイン時のエージェント認証ウィザード
harness/                VMware Fusion 検証ハーネス (Mac 側で実行)
  vmtest                  vmrun ラッパー CLI
  asserts/                ゲスト内で実行する状態アサーション (レベル 1)
  e2e/                    実キー入力 E2E テスト (レベル 3、flaky 許容)
tests/                  静的検証と冪等性テスト
docs/                   VM の構築手順とハーネスの使い方
```

### モジュールの単体実行

```bash
sudo ./install.sh 30-xremap.sh   # モジュール名で指定
sudo ./install.sh 30             # 番号だけでも指定できる
sudo ./install.sh --list         # 一覧を表示
sudo bash modules/30-xremap.sh   # 直接実行もできる
```

---

## 使い方

### 1. プロビジョニング

```bash
sudo ./install.sh
```

完了したら再起動する。dconf のシステム既定値・GNOME 拡張・systemd ユーザーサービスは
再ログインで反映される。

### 2. 初回ログイン

初回ログイン時に `first-run-wizard` が Ghostty で自動起動し、次を対話的に案内する。

1. Claude Code のログイン (`claude auth login`)
2. GitHub 認証 (`gh auth login`) と Copilot CLI のセットアップ
3. opencode の認証設定
4. `herdr integration install claude`
5. Playwright MCP のユーザースコープ登録と herdr-reviewr の導入

各ステップは `s` でスキップ、`q` で中断できる。完了すると
`~/.config/mk-ubuntu/wizard-done` が作られ、以後は自動起動しない。
やり直すときは `first-run-wizard --force`。

**API キーや認証情報はリポジトリに一切含めず、焼き込みもしない。**
認証は各エージェント自身のログインコマンドが行う。

### 3. 検証

```bash
./tests/lint.sh            # bash -n + shellcheck
./tests/static-checks.sh   # リポジトリ構造とパスの静的検証
./harness/vmtest full      # VM 実機検証 (詳細は docs/vm-testing.md)
```

---

## 実現する体験

### Mac 風のキー操作

- CapsLock が Ctrl になる
- Alt+C / Alt+V / Alt+X / Alt+Z / Alt+A / Alt+S / Alt+F / Alt+T / Alt+W が
  Mac の Command 相当として働く
- Ctrl+P / Ctrl+N / Ctrl+B / Ctrl+F でカーソル移動、Ctrl+A / Ctrl+E で行頭・行末、
  Ctrl+H / Ctrl+D で削除、Ctrl+K で行末まで削除
- **ターミナル (Ghostty / Ptyxis) はこのグローバルリマップから除外している。**
  ターミナル内の Alt+C / Alt+V は Ghostty のネイティブ keybind が担当する。
  こうしないと Ctrl+C の中断が壊れる。

### ワークスペース

- 固定 10 ワークスペース
- Ctrl+1 〜 Ctrl+0 で移動、Ctrl+Shift+1 〜 Ctrl+Shift+0 でウィンドウを移動
- Ghostty はワークスペース 1、Brave はワークスペース 2 に自動配置

割当を変えるには `/etc/dconf/db/local.d/40-workspaces` の `application-list` を編集し、
`sudo dconf update` を実行する。書式は `'<desktop ファイル名>:<ワークスペース番号>'`。

```
application-list=['com.mitchellh.ghostty.desktop:1', 'brave-browser.desktop:2', 'code.desktop:3']
```

ユーザー単位で変えたい場合は「拡張機能」アプリの Auto Move Windows の設定から変更できる
(ユーザーの設定がシステム既定値より優先される)。

### シェル

- 新規ユーザーの既定シェルは zsh
- Ctrl+R でコマンド履歴のあいまい検索
- Ctrl+T でファイル一覧 + プレビュー
- 入力補完 (グレー表示のサジェスト) とシンタックスハイライト
- `bat` が使える (Ubuntu の実体は `batcat`)

### AI エージェント

`claude` / `copilot` / `opencode` / `herdr` がシステムワイドに入っている。
Claude Code からは Playwright MCP でブラウザを操作でき、
`herdr-ops` スキルで herdr を操作できる。

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

### 外部 apt リポジトリは Brave のみ

原則として外部 apt リポジトリは追加しない。**Brave (`15-brave.sh`) だけを例外**とする。
Brave は個別バージョンの固定 URL を公開しておらず、リポジトリのローリング配信だけを提供している。
そのため Brave はバージョン固定せず、**リポジトリ署名 (`Signed-By`) を信頼の根拠**とする。
他の外部バイナリはすべてバージョン固定 + SHA256 検証を行う。

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

### xremap の systemd ユニット

- パスに `/home/<user>` を書かず `%h` を使う
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

**ディスクサイズへの影響**: Chromium のみで約 400 MB。
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

### VM 検証での描画性能について

Ghostty の GPU 描画は **OpenGL 4.3 以上**を必要とする。VMware Fusion のゲストでは
ソフトウェアレンダリングにフォールバックするため、
**VM 上で観測した描画性能は参考値**であり実機の値ではない。
描画品質の確認は `docs/vm-testing.md` の手動チェックリストに回している。

---

## バージョン固定の一覧

外部から取得するものはすべて各モジュール冒頭の変数で固定している。

| 対象 | バージョン | 固定箇所 | 検証 |
| --- | --- | --- | --- |
| zimfw | v1.20.0 | `modules/20-zsh-zimfw.sh` | SHA256 |
| xremap | v0.15.10 | `modules/30-xremap.sh` | SHA256 |
| xremap GNOME 拡張 | v15 | リポジトリに同梱 | SHA256 (`tests/static-checks.sh`) |
| herdr | 0.8.0 | `modules/50-herdr.sh` | SHA256 |
| Claude Code | 2.1.231 | `modules/60-agents.sh` | npm のバージョン指定 |
| GitHub Copilot CLI | 1.0.79 | `modules/60-agents.sh` | npm のバージョン指定 |
| opencode | 1.18.18 | `modules/60-agents.sh` | SHA256 |
| Playwright MCP | 0.0.79 | `modules/65-agent-tooling.sh` | npm のバージョン指定 |
| herdr-reviewr | v0.30.4 | `bin/first-run-wizard` | `--ref` によるリビジョン固定 |
| Brave | 固定しない | — | apt リポジトリ署名 (`Signed-By`) |

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

ハーネスの詳細は [docs/vm-testing.md](docs/vm-testing.md)、
VM の初期構築は [docs/vm-setup.md](docs/vm-setup.md) を参照。

### 冪等性の考え方

- ファイル配置は `install_file` / `write_file` を使う (内容が同じなら書かない)
- 設定ファイルの書き換えは `set_conf_key` を使う (追記ではなく置換なので行が増えない)
- apt は未導入のものだけを対象にする
- 外部バイナリはバージョンを確認し、一致していればダウンロードしない
- `dconf` は生成ファイルの内容が同じなら差分が出ない

冪等性は `tests/state-manifest.sh` が出す状態スナップショットの差分で判定する。
`vmtest full` は `install.sh` を 2 回実行して、この出力に差分がないことを確認する。

---

## ライセンス

このリポジトリのスクリプトと設定ファイルについては、リポジトリのライセンス表記に従う。

導入する第三者ソフトウェアのライセンスには注意が必要。特に:

- **herdr は AGPL-3.0 / 商用のデュアルライセンス。**
  本リポジトリの成果物 (プロビジョニング済みイメージや ISO) を外部配布する場合は、
  条件確認が必要。
- xremap は MIT、xremap の GNOME 拡張は GPLv2+。
- Brave、Claude Code、GitHub Copilot CLI はそれぞれの利用規約に従う。
- `files/gnome-extensions/` に同梱している zip は extensions.gnome.org の配布物
  (xremap GNOME Shell 拡張、GPLv2+)。
- `files/claude-skills/herdr-ops/SKILL.md` は herdr v0.8.0 の
  `skills/herdr/SKILL.md` の写し。
