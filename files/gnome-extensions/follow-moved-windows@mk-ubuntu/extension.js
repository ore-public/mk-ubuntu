// Auto Move Windows が振り分けたウィンドウを追いかけてワークスペースを切り替える。
//
// GNOME 標準の Auto Move Windows は window.change_workspace_by_index() で
// ウィンドウを移すだけで、表示中のワークスペースは切り替えない。
// そのためアプリを起動しても手元の画面は変わらず、「準備ができました」という
// 通知が出るだけになる。
//
// この拡張は、Auto Move Windows と同じ設定 (application-list) を読み、
// 振り分け対象のウィンドウが実際にそのワークスペースへ移動していたら
// window.activate() を呼ぶ。activate はワークスペースの切り替えと
// フォーカスの両方を行うので、結果として「アプリと一緒に移動する」挙動になる。
//
// 対象は application-list に載っているアプリだけ。それ以外のウィンドウが
// 別のワークスペースで開いても画面は動かさない。

import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Shell from 'gi://Shell';
import { Extension } from 'resource:///org/gnome/shell/extensions/extension.js';

const AUTO_MOVE_SCHEMA = 'org.gnome.shell.extensions.auto-move-windows';

// Auto Move Windows がウィンドウを移し終えるのを待つ時間 (ミリ秒)。
// どちらも window-created を契機に動くため、こちらが後になるようにずらす。
const FOLLOW_DELAY_MS = 250;

export default class FollowMovedWindows extends Extension {
  enable() {
    this._settings = new Gio.Settings({ schema_id: AUTO_MOVE_SCHEMA });
    this._tracker = Shell.WindowTracker.get_default();
    this._timeouts = new Set();

    this._windowCreatedId = global.display.connect(
      'window-created',
      (_display, window) => this._onWindowCreated(window)
    );
  }

  disable() {
    if (this._windowCreatedId) {
      global.display.disconnect(this._windowCreatedId);
      this._windowCreatedId = null;
    }

    this._timeouts?.forEach(id => GLib.Source.remove(id));
    this._timeouts = null;

    this._settings = null;
    this._tracker = null;
  }

  _onWindowCreated(window) {
    if (!window || window.skip_taskbar || window.is_on_all_workspaces())
      return;

    const id = GLib.timeout_add(GLib.PRIORITY_DEFAULT, FOLLOW_DELAY_MS, () => {
      this._timeouts?.delete(id);
      this._follow(window);
      return GLib.SOURCE_REMOVE;
    });
    this._timeouts.add(id);
  }

  // application-list から、そのアプリの行き先ワークスペース番号 (0 始まり) を得る。
  // 載っていなければ null。
  _targetWorkspaceIndex(appId) {
    const entries = this._settings?.get_strv('application-list') ?? [];

    for (const entry of entries) {
      const separator = entry.lastIndexOf(':');
      if (separator < 0)
        continue;

      if (entry.slice(0, separator) !== appId)
        continue;

      const index = parseInt(entry.slice(separator + 1), 10) - 1;
      return Number.isInteger(index) && index >= 0 ? index : null;
    }

    return null;
  }

  _follow(window) {
    // タイマーの間にウィンドウが閉じられていることがある
    if (!window || !window.get_compositor_private())
      return;

    const app = this._tracker?.get_window_app(window);
    if (!app)
      return;

    const target = this._targetWorkspaceIndex(app.get_id());
    if (target === null)
      return;

    const workspace = window.get_workspace();
    if (!workspace)
      return;

    // Auto Move Windows がまだ動いていない、または別の場所にいるなら何もしない
    if (workspace.index() !== target)
      return;

    // 既にそのワークスペースを見ているなら切り替え不要
    if (workspace.active)
      return;

    window.activate(global.get_current_time());
  }
}
