import 'dart:io';

/// Local pages keep the example usable without an external website or server.
class DemoPageServer {
  DemoPageServer._(this._server) {
    _server.listen((request) async {
      // Downloads: an attachment and a type the WebView cannot show.
      if (request.uri.path == '/download/report.csv') {
        request.response.headers
          ..contentType = ContentType('text', 'csv')
          ..set('Content-Disposition', 'attachment; filename="report.csv"');
        request.response.write('name,value\nalpha,1\nbeta,2\n');
        await request.response.close();
        return;
      }
      if (request.uri.path == '/download/data.bin') {
        request.response.headers.contentType = ContentType.binary;
        request.response.add(List<int>.generate(1024, (i) => i % 256));
        await request.response.close();
        return;
      }
      final id = int.tryParse(request.uri.queryParameters['id'] ?? '') ?? 0;
      final next = request.uri.path == '/next';
      request.response.headers.contentType = ContentType.html;
      request.response.write(page(id, next: next));
      await request.response.close();
    });
  }

  final HttpServer _server;
  int get port => _server.port;
  String url(int id) => 'http://127.0.0.1:$port/?id=$id';

  static Future<DemoPageServer> start() async => DemoPageServer._(
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      );

  Future<void> close() async => _server.close(force: true);

  static String page(int id, {bool next = false}) {
    final prompt = Platform.isMacOS
        ? '<button onclick="askFlutter()">Prompt Flutter</button>'
        : '';
    return '''<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Browser $id${next ? ' · page 2' : ''}</title>
<style>
:root {
  color-scheme: light dark; font: 15px/1.5 system-ui, sans-serif;
  --bg: #f6f7fb; --card: #fff; --line: #e3e5ee; --muted: #6b7080;
  --accent: #4f5bd5; --accent-text: #fff; --soft: #eef0fb;
}
@media (prefers-color-scheme: dark) {
  :root { --bg: #15161b; --card: #1e2027; --line: #2e313b; --muted: #9a9fb0;
    --accent: #8f98ff; --accent-text: #11131a; --soft: #262941; }
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); }
main { max-width: 860px; margin: 0 auto; padding: 32px 24px 48px; }
header { display: flex; align-items: center; gap: 16px; margin-bottom: 24px; }
.badge { width: 52px; height: 52px; border-radius: 14px; display: grid; place-items: center;
  background: var(--accent); color: var(--accent-text); font-size: 22px; font-weight: 700; }
.eyebrow { margin: 0; color: var(--muted); font-size: 12px; letter-spacing: .08em; text-transform: uppercase; }
h1 { margin: 0; font-size: 26px; }
.grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(340px, 1fr)); gap: 16px; }
section { background: var(--card); border: 1px solid var(--line); border-radius: 14px; padding: 18px 20px; }
h2 { margin: 0 0 4px; font-size: 16px; }
p.note { margin: 0 0 14px; color: var(--muted); font-size: 13px; }
.row { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; }
button, input, a.button, label.button { font: inherit; border-radius: 8px; padding: 7px 12px; }
button, a.button, label.button { border: 1px solid var(--line); background: var(--soft); color: inherit;
  cursor: pointer; text-decoration: none; }
button.primary { background: var(--accent); color: var(--accent-text); border-color: transparent; }
input { flex: 1; min-width: 0; border: 1px solid var(--line); background: transparent; color: inherit; }
ul.log { list-style: none; margin: 12px 0 0; padding: 0; max-height: 180px; overflow: auto;
  font: 12.5px/1.5 ui-monospace, monospace; }
ul.log li { padding: 6px 10px; border-radius: 8px; background: var(--soft); margin-bottom: 6px;
  overflow-wrap: anywhere; }
ul.log li span { color: var(--muted); margin-right: 8px; }
ul.log:empty::before { content: 'Nothing yet.'; color: var(--muted); }
code, .mono { font: 12.5px ui-monospace, monospace; overflow-wrap: anywhere; }
dl { display: grid; grid-template-columns: max-content 1fr; gap: 6px 14px; margin: 0; font-size: 13px; }
dt { color: var(--muted); }
dd { margin: 0; }
</style></head><body><main>
<header>
  <div class="badge">$id</div>
  <div><p class="eyebrow">desktop_webview_window · demo page</p>
  <h1>Browser $id${next ? ' · page 2' : ''}</h1></div>
</header>
<div class="grid">
<section>
  <h2>Messages</h2>
  <p class="note">Talk to Flutter through <code>window.desktopWebview</code>. Messages from the app's Messages tab land below.</p>
  <div class="row"><input id="message" value="Hello from browser $id">
  <button class="primary" onclick="sendToApp()">Send to Flutter</button>$prompt</div>
  <ul class="log" id="log"></ul>
</section>
<section>
  <h2>Navigation</h2>
  <p class="note">Use the native toolbar, the sidebar or the app's address bar to go back and forward.</p>
  <div class="row">
    <a class="button" href="${next ? '/' : '/next'}?id=$id">${next ? '← Page 1' : 'Page 2 →'}</a>
    <button onclick="location.reload()">Reload</button>
    <button id="clicker" onclick="this.textContent = 'Clicked ' + (++clicks) + '×'">Click me</button>
  </div>
  <div class="row" style="margin-top:10px"><input placeholder="Native text input"></div>
</section>
<section>
  <h2>Cookies</h2>
  <p class="note">All windows share one profile. Use Read cookies in the app's Cookies tab.</p>
  <div class="row">
    <button onclick="document.cookie='demo_window_$id=hello; path=/; SameSite=Lax'; showCookies()">Set cookie</button>
    <button onclick="document.cookie='demo_window_$id=; max-age=0; path=/'; showCookies()">Delete cookie</button>
  </div>
  <p class="mono" id="cookies" style="margin:12px 0 0"></p>
</section>
<section>
  <h2>Page UI</h2>
  <p class="note">Native browser UI the page opens itself. Right-click anywhere for the context menu.</p>
  <div class="row">
    <button onclick="alert('Hello from browser $id')">Alert</button>
    <button onclick="addLog('Confirm ←', confirm('Continue?'))">Confirm</button>
    <label class="button">Upload files<input type="file" multiple hidden
      onchange="addLog('Files ←', [...this.files].map(f => f.name + ' (' + f.size + ' B)').join(', ') || 'none'); this.value = ''"
      oncancel="addLog('Files ←', 'cancelled')"></label>
  </div>
  <div class="row" style="margin-top:10px">
    <a class="button" href="/download/report.csv">Download attachment</a>
    <a class="button" href="/download/data.bin">Download binary</a>
  </div>
  <div class="row" style="margin-top:10px">
    <a class="button" href="/next?id=$id" target="_blank">target=_blank</a>
    <button onclick="window.open('/next?id=$id')">window.open</button>
    <button onclick="setTimeout(() => window.open('/next?id=$id'), 500)">window.open later</button>
    <a class="button" href="mixin://users/demo">mixin:// link</a>
  </div>
</section>
<section>
  <h2>Environment</h2>
  <p class="note">Values the app can also read from its JavaScript tab.</p>
  <dl>
    <dt>URL</dt><dd class="mono" id="url"></dd>
    <dt>Bridge</dt><dd id="bridge"></dd>
    <dt>User agent</dt><dd class="mono" id="ua"></dd>
  </dl>
</section>
</div>
</main>
<script>
let clicks = 0;
function addLog(direction, value) {
  const item = document.createElement('li');
  const tag = document.createElement('span');
  tag.textContent = direction;
  item.append(tag, typeof value === 'string' ? value : JSON.stringify(value));
  const log = document.getElementById('log');
  log.prepend(item);
  while (log.children.length > 20) log.lastChild.remove();
}
function showCookies() {
  document.getElementById('cookies').textContent = document.cookie || 'No cookies for this page.';
}
window.receiveFromApp = function(message) { addLog('Flutter →', message); return 'Received: ' + message; };
function sendToApp() {
  const payload = {window: $id, message: document.getElementById('message').value};
  window.desktopWebview.postMessage('demo', payload);
  addLog('→ Flutter', payload);
}
function askFlutter() { addLog('Prompt ←', prompt('Demo prompt', 'Browser $id')); }
window.desktopWebview.addEventListener('demo', data => addLog('Flutter →', data));
document.getElementById('url').textContent = location.href;
document.getElementById('bridge').textContent = window.desktopWebview ? 'window.desktopWebview ready' : 'missing';
document.getElementById('ua').textContent = navigator.userAgent;
showCookies();
</script></body></html>''';
  }
}
