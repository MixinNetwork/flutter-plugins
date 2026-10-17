import 'dart:convert';

/// Name of the native script message handler on WebKit platforms.
const javaScriptBridgeHandler = 'desktopWebview';

/// Injected at document start in the top-level frame on every platform.
///
/// Pages use `window.desktopWebview.postMessage(name, data)` and
/// `window.desktopWebview.addEventListener(name, listener)`. Messages travel as
/// JSON strings `{name, data}` over `webkit.messageHandlers.desktopWebview`
/// (macOS, Linux) or `chrome.webview` (Windows).
const javaScriptBridgeSource = r'''
(() => {
  if (window.desktopWebview) return;
  const listeners = new Map();
  const webkit = window.webkit && window.webkit.messageHandlers &&
      window.webkit.messageHandlers.desktopWebview;
  const chrome = window.chrome && window.chrome.webview;
  const send = (raw) => {
    if (webkit) webkit.postMessage(raw);
    else if (chrome) chrome.postMessage(raw);
    else throw new Error('desktopWebview bridge is unavailable');
  };
  const dispatch = (raw) => {
    let message;
    try {
      message = typeof raw === 'string' ? JSON.parse(raw) : raw;
    } catch (_) {
      return;
    }
    if (!message || typeof message.name !== 'string') return;
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
        send(JSON.stringify({
          name: String(name),
          data: data === undefined ? null : data,
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

/// Encodes a Dart-to-page message.
String encodeJavaScriptMessage(String name, Object? data) =>
    jsonEncode({'name': name, 'data': data});

/// Script delivering [message] on WebKit platforms, where native code cannot
/// post a web message directly.
String javaScriptDispatchScript(String message) =>
    'window.desktopWebview && window.desktopWebview._dispatch('
    '${jsonEncode(message)});';

/// Decodes a page-to-Dart message, or null when it is not a bridge message.
({String name, Object? data})? decodeJavaScriptMessage(String raw) {
  final Object? value;
  try {
    value = jsonDecode(raw);
  } on FormatException {
    return null;
  }
  if (value is! Map || value['name'] is! String) return null;
  return (name: value['name'] as String, data: value['data']);
}
