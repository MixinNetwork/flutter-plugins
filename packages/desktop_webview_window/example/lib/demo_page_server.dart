import 'dart:io';

/// Local pages keep the example usable without an external website or server.
class DemoPageServer {
  DemoPageServer._(this._server) {
    _server.listen((request) async {
      final id = int.tryParse(request.uri.queryParameters['id'] ?? '') ?? 0;
      final next = request.uri.path == '/next';
      request.response.headers.contentType = ContentType.html;
      request.response.write('''<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Browser $id${next ? ' next' : ''}</title>
<style>
:root { color-scheme: light dark; font: 16px system-ui; }
body { max-width: 720px; margin: 48px auto; padding: 0 24px; }
h1 { font-size: 32px; } section { margin: 24px 0; padding: 20px; border: 1px solid #8886; border-radius: 12px; }
button, input, a { font: inherit; margin: 6px 8px 6px 0; padding: 8px; }
output { display: block; margin-top: 12px; white-space: pre-wrap; overflow-wrap: anywhere; }
</style></head><body>
<p>DESKTOP WEBVIEW WINDOW</p><h1>Browser $id${next ? ' · next page' : ''}</h1>
<p>This native browser has its own page. Use the Flutter app to control this window and inspect its events.</p>
<section><h2>Navigation & input</h2><label>Native input <input placeholder="Type here"></label>
<button onclick="this.textContent='Clicked browser $id'">Native button</button>
<a href="${next ? '/' : '/next'}?id=$id">${next ? 'First page' : 'Next page'}</a></section>
<section><h2>Messages</h2><input id="message" value="Hello from browser $id">
<button onclick="sendToApp()">Send to Flutter</button>
${Platform.isMacOS ? '<button onclick="showResult(prompt(\'Demo prompt\', \'Browser $id\'))">Prompt Flutter</button>' : ''}
<output id="result">Messages from Flutter appear here.</output></section>
<section><h2>Cookies</h2>
<button onclick="document.cookie='demo_window_$id=hello; path=/; SameSite=Lax'; showResult(document.cookie)">Set cookie</button>
<button onclick="document.cookie='demo_window_$id=; max-age=0; path=/'; showResult(document.cookie)">Delete cookie</button>
<p>Use Read cookies in Flutter to inspect the shared browser profile.</p></section>
<script>
function showResult(value) { document.getElementById('result').textContent = String(value); }
window.receiveFromApp = function(message) { showResult(message); return 'Received: ' + message; };
function sendToApp() {
  const payload = {window: $id, message: document.getElementById('message').value};
  if (window.chrome && window.chrome.webview) window.chrome.webview.postMessage(JSON.stringify(payload));
  else if (window.webkit && window.webkit.messageHandlers.demo) window.webkit.messageHandlers.demo.postMessage(JSON.stringify(payload));
  showResult('Sent to Flutter: ' + JSON.stringify(payload));
}
if (window.chrome && window.chrome.webview) window.chrome.webview.addEventListener('message', e => showResult(JSON.stringify(e.data)));
</script></body></html>''');
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
}
