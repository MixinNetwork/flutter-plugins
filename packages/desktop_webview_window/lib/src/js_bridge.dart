import 'dart:convert';
import 'dart:math';

/// Name of the native script message handler on WebKit platforms.
const javaScriptBridgeHandler = 'desktopWebview';

/// A random per-browser prefix of bridge messages.
///
/// WebKit exposes `webkit.messageHandlers` to every frame, including
/// cross-origin iframes on Linux, but only the top-level document runs the
/// bridge. The token lives in the bridge's closure, so other frames cannot
/// produce a message that [decodeJavaScriptMessage] accepts.
String createJavaScriptBridgeToken() {
  final random = Random.secure();
  return [
    for (var i = 0; i < 16; i++)
      random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}

/// Injected at document start in the top-level frame on every platform.
///
/// Pages use `window.desktopWebview.postMessage(name, data)` and
/// `window.desktopWebview.addEventListener(name, listener)`. Messages travel as
/// [token] followed by the JSON string `{name, data, url}` over
/// `webkit.messageHandlers.desktopWebview` (macOS, Linux) or `chrome.webview`
/// (Windows). Functions are captured before page scripts run. `url` is the
/// document's current `location.href`; Dart keeps it only when it matches the
/// origin native code reports for the sender.
///
/// A Dart-to-page message with a `targetOrigin` reaches listeners only while
/// the document's origin, serialized like [javaScriptMessageOrigin], equals
/// it. The check runs in the receiving document, so a reply cannot reach a
/// page the window navigated to after the reply was sent.
String javaScriptBridgeSource(String token) => '''
(() => {
  if (window.desktopWebview) return;
  const token = ${jsonEncode(token)};
  const stringify = JSON.stringify;
  const parse = JSON.parse;
  const hasOwn = Function.prototype.call.bind(Object.prototype.hasOwnProperty);
  // Location members cannot be redefined by the page.
  const currentOrigin = () =>
      location.protocol === 'file:' ? 'file://' : location.origin;
  const listeners = new Map();
  const webkit = window.webkit && window.webkit.messageHandlers &&
      window.webkit.messageHandlers.desktopWebview;
  const chrome = window.chrome && window.chrome.webview;
  const post = webkit ? webkit.postMessage.bind(webkit)
      : chrome ? chrome.postMessage.bind(chrome) : null;
  const send = (raw) => {
    if (!post) throw new Error('desktopWebview bridge is unavailable');
    post(token + raw);
  };
  const dispatch = (raw) => {
    let message;
    try {
      message = typeof raw === 'string' ? parse(raw) : raw;
    } catch (_) {
      return;
    }
    if (!message || typeof message.name !== 'string') return;
    if (hasOwn(message, 'targetOrigin')) {
      const origin = currentOrigin();
      if (origin === 'null' || origin !== message.targetOrigin) return;
    }
    const set = listeners.get(message.name);
    if (!set) return;
    for (const listener of [...set]) {
      try {
        listener(message.data);
      } catch (error) {
        setTimeout(() => { throw error; });
      }
    }
  };
  if (chrome) chrome.addEventListener('message', (event) => dispatch(event.data));
  Object.defineProperty(window, 'desktopWebview', {
    configurable: false,
    writable: false,
    value: Object.freeze({
      postMessage(name, data) {
        send(stringify({
          name: String(name),
          data: data === undefined ? null : data,
          url: location.href,
        }));
      },
      addEventListener(name, listener) {
        const key = String(name);
        if (!listeners.has(key)) listeners.set(key, new Set());
        listeners.get(key).add(listener);
      },
      removeEventListener(name, listener) {
        const set = listeners.get(String(name));
        if (set) set.delete(listener);
      },
      _dispatch: dispatch,
    }),
  });
})();
''';

/// Encodes a Dart-to-page message. [targetOrigin] must already be a
/// serialized origin; see [javaScriptTargetOrigin].
String encodeJavaScriptMessage(
  String name,
  Object? data, {
  String? targetOrigin,
}) =>
    jsonEncode({
      'name': name,
      'data': data,
      if (targetOrigin != null) 'targetOrigin': targetOrigin,
    });

/// Normalizes a `postMessage` target like `window.postMessage`: `*` means
/// any document and returns null, a URL stands for its origin. Throws when
/// [targetOrigin] has no origin a document could match.
String? javaScriptTargetOrigin(String? targetOrigin) {
  if (targetOrigin == null || targetOrigin == '*') return null;
  final origin = javaScriptMessageOrigin(targetOrigin);
  if (origin == 'null') {
    throw ArgumentError.value(
      targetOrigin,
      'targetOrigin',
      'Must be "*", an HTTP(S) or file URL',
    );
  }
  return origin;
}

/// Script delivering [message] on WebKit platforms, where native code cannot
/// post a web message directly.
String javaScriptDispatchScript(String message) =>
    'window.desktopWebview && window.desktopWebview._dispatch('
    '${jsonEncode(message)});';

/// Decodes a page-to-Dart message, or null when it is not a bridge message
/// carrying [token].
({String name, Object? data, String? url})? decodeJavaScriptMessage(
    String raw, String token) {
  if (!raw.startsWith(token)) return null;
  final Object? value;
  try {
    value = jsonDecode(raw.substring(token.length));
  } on FormatException {
    return null;
  }
  if (value is! Map || value['name'] is! String) return null;
  final url = value['url'];
  return (
    name: value['name'] as String,
    data: value['data'],
    url: url is String ? url : null,
  );
}

/// Serializes the origin of the document at [source]: `scheme://host[:port]`
/// for HTTP(S), `file://` for local files and `null` for opaque origins.
String javaScriptMessageOrigin(String? source) {
  final uri = source == null ? null : Uri.tryParse(source);
  if (uri == null) return 'null';
  final scheme = uri.scheme.toLowerCase();
  if ((scheme == 'http' || scheme == 'https') && uri.host.isNotEmpty) {
    return uri.origin;
  }
  return scheme == 'file' ? 'file://' : 'null';
}

/// [url] as reported by the sending document when it is an HTTP(S) or file
/// URL of [origin], the origin native code reported, otherwise null.
///
/// The document chooses [url], but only within its own origin, which it can
/// reach anyway with `history.pushState`. Native URLs are not used: WebView2
/// reports the URL the document was loaded with.
Uri? javaScriptMessageUrl(String? url, String origin) {
  if (origin == 'null' || url == null) return null;
  final uri = Uri.tryParse(url);
  if (uri == null || javaScriptMessageOrigin(url) != origin) return null;
  return uri;
}
