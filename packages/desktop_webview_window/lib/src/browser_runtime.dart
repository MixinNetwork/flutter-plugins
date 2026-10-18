import 'package:flutter/services.dart';

import 'native_transport.dart';
import 'webview_impl.dart';

// Open browsers by ID.
final browsers = <int, WebviewImpl>{};

// Browsers whose native close arrived before their create call returned.
int pendingCreates = 0;
final closedDuringCreate = <int>{};

NativeTransport? _attachedTransport;

/// Routes native events of the current transport to browsers.
NativeTransport attachTransport() {
  final transport = NativeTransport.instance;
  if (identical(_attachedTransport, transport)) return transport;
  _attachedTransport = transport;
  transport.onEvent = _handleEvent;
  transport.onNavigationRequest = decideNavigation;
  return transport;
}

// A navigation of a browser Dart no longer tracks proceeds.
bool decideNavigation(int id, String url) =>
    browsers[id]?.decideNavigation(url) ?? true;

Future<Object?> _handleEvent(MethodCall call) async {
  final args = (call.arguments as Map?) ?? const {};
  final id = args['id'] as int;
  final webview = browsers[id];
  if (webview == null) {
    if (call.method == 'onWindowClose' && pendingCreates > 0) {
      closedDuringCreate.add(id);
    }
    return call.method == 'onUrlRequest' ? true : null;
  }
  switch (call.method) {
    case 'onWindowClose':
      browsers.remove(id);
      webview.onClosed();
    case 'onJavaScriptMessage':
      webview.onJavaScriptMessage(
          args['message'] as String, args['source'] as String?);
    case 'runJavaScriptTextInputPanelWithPrompt':
      return webview.onPrompt(
          args['prompt'] as String, args['defaultText'] as String);
    case 'onNavigationStateChanged':
      webview.onNavigationStateChanged(
        canGoBack: args['canGoBack'] as bool,
        canGoForward: args['canGoForward'] as bool,
        isLoading: args['isLoading'] as bool,
        url: args['url'] as String?,
        title: args['title'] as String?,
      );
    case 'onUrlRequest':
      return webview.decideNavigation(args['url'] as String);
    default:
      throw MissingPluginException(call.method);
  }
  return null;
}
