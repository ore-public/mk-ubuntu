# ハーネスの使い方と手動検証チェックリスト

VM の初期構築 (スナップショット `clean` の作成) は [vm-setup.md](vm-setup.md) を参照。

---

## 1. ハーネス (`harness/vmtest`) の使い方

Mac 側で実行する。`harness/config.env` が必要。

| コマンド | 内容 |
| --- | --- |
| `./harness/vmtest reset` | `clean` へ復元 → 起動 → IP 取得 → SSH 疎通待ち |
| `./harness/vmtest reboot` | ゲストを再起動し、SSH が戻るまで待つ |
| `./harness/vmtest sync` | リポジトリを rsync でゲストの `~/distro-setup/` へ転送 |
| `./harness/vmtest provision` | ゲストで `sudo ./install.sh` を実行し、ログを `harness/logs/` に保存 |
| `./harness/vmtest assert` | `harness/asserts/` をゲスト実行し、TAP 形式で集約出力 |
| `./harness/vmtest shot <名前>` | 画面キャプチャを `harness/shots/<名前>.png` に保存 |
| `./harness/vmtest e2e` | 実キー入力 E2E テスト (flaky 許容、1 回リトライ) |
| `./harness/vmtest full` | 上記を通しで実行し、冪等性 (2 回実行して差分なし) も確認 |
| `./harness/vmtest ssh [cmd]` | ゲストへ SSH (デバッグ用) |

### `vmtest full` の流れ

```
reset → sync → provision(1回目) → 状態マニフェスト記録
     → reboot → assert
     → provision(2回目) → 状態マニフェスト記録 → マニフェスト差分ゼロを確認
     → assert → shot → e2e
```

終了コードには **レベル 1 (assert) と冪等性の結果だけ**が反映される。
e2e (レベル 3) の失敗は警告として出力されるが、終了コードには含めない。

### ログの読み方

- `harness/logs/<日時>-provision-N.log` — `install.sh` の全出力
- `harness/logs/<日時>-assert.log` — TAP 形式の検証結果
- `harness/.state/manifest.diff` — 冪等性が崩れたときの差分
- `harness/shots/*.png` — 画面キャプチャ

TAP の読み方: `ok N 説明` が成功、`not ok N 説明` が失敗、`# ` から始まる行は診断情報。
末尾に `1..N` と合計・失敗数が出る。

### 失敗時のトリアージ

1. `not ok` の行と、その直後の `#` 診断行を読む
2. 該当モジュールの provision ログを見て、実際に何が実行されたか確認する
3. GUI が絡む項目は `harness/shots/` の画像を見る
4. 個別に再現するときは `./harness/vmtest ssh 'bash ~/distro-setup/harness/asserts/30-xremap.sh'`

---

## 2. 検証の 3 レベル

| レベル | 場所 | 判定 | 内容 |
| --- | --- | --- | --- |
| 1. 状態アサーション | `harness/asserts/` | 自動 | ファイル配置・dconf 既定値・バージョン・新規ユーザー継承・冪等性 |
| 2. スクリーンショット | `vmtest shot` | Claude が画像を読んで判断 | ワークスペース自動配置、ウィザード起動、デスクトップの破綻 |
| 3. 実キー入力 E2E | `harness/e2e/` | 自動 (flaky 許容) | ydotool で注入したキーが xremap でどう変換されるか |

検証項目の大半はレベル 1 に寄せてある。

### レベル 2 の見どころ

`vmtest shot` で撮った画像で次を確認する。

- Ghostty がワークスペース 1、Brave がワークスペース 2 に自動配置されているか
- 初回ログイン時に first-run-wizard の画面が出ているか
- パネル・Dock・壁紙などデスクトップ全体に破綻がないか

### レベル 3 の限界

`harness/e2e/10-key-remap.sh` は ydotool でキーイベントを注入し、
xremap が作る仮想入力デバイスを `probe.py` で読んで変換結果を確認する。

`keymap` の確認 (Ctrl-p → Up、Alt-c → Ctrl-c) はフォーカス中のウィンドウの
WM_CLASS を見て `application:` 条件を評価するため、非ターミナルのウィンドウが
フォーカスされていないと 1 つも適用されない。スクリプトは事前に
gnome-text-editor などを開いてフォーカスを作る。

それでもタイミングに依存するため不安定。失敗しても実機の手動確認に回す
(`vmtest full` の終了コードには含めない)。

`vmtest shot` には `config.env` の `GUEST_PASSWORD` が必要。
`vmrun captureScreen` がゲストへのログインを要求するため。
未設定なら撮影を飛ばして先へ進む (レベル 1 の判定には影響しない)。

---

## 3. 手動検証チェックリスト

自動化していない項目。**実機 (できれば x86_64) で確認する。**
VM でも確認できるが、描画品質と打鍵感は実機の値と異なる。

### ランチャー / Quick Look / スクリーンショット

- [ ] F12 で Vicinae が開き、アプリ名を打つと起動できる
- [ ] Vicinae の Clipboard History に、コピーした内容の履歴が並ぶ
- [ ] Files でファイルを選んでスペースキーを押すとプレビューが出る (Quick Look)
- [ ] Alt+Shift+3 で画面全体のスクリーンショットが撮れる
- [ ] Alt+Shift+4 / Alt+Shift+5 で撮影パネルが出て範囲選択できる
- [ ] Print キーの既定の撮影も引き続き使える

### トラックパッド (実機必須。VM では確認できない)

- [ ] 1 本指のタップでクリックできる
- [ ] 2 本指のタップで右クリックメニューが出る
- [ ] タップしてそのままドラッグできる
- [ ] スクロール方向が macOS と同じ (ナチュラル)

### キーリマップ (F3)

- [ ] CapsLock を押すと Ctrl として働く (CapsLock+C でコピーできる)
- [ ] テキストエディタで Ctrl+P / Ctrl+N でカーソルが上下に動く
- [ ] Ctrl+B / Ctrl+F でカーソルが左右に動く
- [ ] Ctrl+A / Ctrl+E で行頭 / 行末に移動する
- [ ] Ctrl+H で 1 文字削除、Ctrl+D で後方 1 文字削除
- [ ] Ctrl+K でカーソル位置から行末まで削除
- [ ] Brave や テキストエディタで Alt+C / Alt+V がコピー / ペーストとして働く
- [ ] Alt+W でウィンドウ (タブ) が閉じる、Alt+T で新規タブが開く
- [ ] Alt+Q でウィンドウが閉じる (Brave / GNOME アプリの両方で)

### ターミナル (F2 / F2.5)

- [ ] Ctrl+Alt+T で **Ghostty** が起動する (Ptyxis ではない)
- [ ] Ghostty 内で Alt+C / Alt+V がコピー / ペーストとして働く (ネイティブ keybind)
- [ ] Ghostty 内で Ctrl+C が「中断」として働く (グローバルリマップの除外が効いている)
- [ ] Ghostty 内で Ctrl+A / Ctrl+E がシェルの行頭 / 行末移動として働く
- [ ] シェルが zsh で、プロンプトに git のブランチ名が出る
- [ ] Ctrl+R でコマンド履歴のあいまい検索ができる
- [ ] Ctrl+T でファイル一覧が出て、右側にプレビューが表示される
- [ ] `bat README.md` がシンタックスハイライト付きで表示される
- [ ] Ghostty の描画品質 (**VM ではソフトウェアレンダリングなので実機で確認する**)

### ワークスペース (F4)

- [ ] Ctrl+1 〜 Ctrl+0 でワークスペース 1 〜 10 に移動できる
- [ ] Ctrl+Shift+1 〜 Ctrl+Shift+0 でウィンドウを移動できる
- [ ] ワークスペースが 10 個固定されている (「アクティビティ」画面で確認)
- [ ] Ghostty を起動するとワークスペース 1 に配置される
- [ ] Brave を起動するとワークスペース 2 に配置される

### ブラウザ (F1.5)

- [ ] メールやドキュメント内のリンクをクリックすると Brave が開く
- [ ] `xdg-open https://example.com` で Brave が開く
- [ ] Firefox も残っていて起動できる

### エージェント (F5 / F6 / F6.5)

- [ ] 初回ログイン時に first-run-wizard が Ghostty で自動起動する
- [ ] ウィザードでスキップ (`s`) と中断 (`q`) が効き、あとで再実行できる
- [ ] `claude` が起動し、ログイン済みになっている
- [ ] `copilot` が起動する
- [ ] `opencode` が起動する
- [ ] `herdr` が起動し、ペインの分割やワークスペース作成ができる
- [ ] Claude Code から Playwright MCP でブラウザ操作ができる
      (例: 「example.com を開いてタイトルを教えて」)
- [ ] Claude Code が herdr-ops スキルを認識する (`/herdr-ops` で呼べる)
- [ ] herdr のペインで herdr-reviewr が開く
- [ ] 2 回目以降のログインではウィザードが自動起動しない

### 設定ファイルの持ち方

- [ ] `~/.zshrc.local` にエイリアスを書いて再ログインすると効く
- [ ] `~/.config/ghostty/config.local` に `font-size = 16` を書くと反映される
- [ ] `~/.zshrc` を書き換えて `sudo ./install.sh` すると元に戻る
      (書き換えは消えるが `~/.zshrc.local` は残る)

### アプリと Docker (amd64 実機で確認)

- [ ] Discord が起動してログインできる
- [ ] Zoom が起動する
- [ ] 1Password が起動してロック解除できる
- [ ] Dropbox が起動し、初回のセットアップ案内が出る
- [ ] `docker run --rm hello-world` が sudo なしで通る (再ログイン後)
- [ ] `docker compose version` が表示される

> arm64 の検証 VM では Discord / Zoom / 1Password / Dropbox は
> 導入されない。ハーネスは「導入されていないこと」までを確認する。

### 新規ユーザー

- [ ] 「設定」→「システム」→「ユーザー」で新規ユーザーを作ると、
      そのユーザーでも上のキー操作・ワークスペース設定がそのまま効く

---

## 4. Claude Code の運用ループ

```
モジュール実装
  → ./tests/lint.sh (bash -n + shellcheck)
  → ./tests/static-checks.sh
  → ./harness/vmtest full
  → 失敗のトリアージ (assert ログ / スクリーンショットを読む)
  → リポジトリ修正
  → 再実行
```

コミットは **`vmtest full` のレベル 1 が全通過していること**を条件とする。
