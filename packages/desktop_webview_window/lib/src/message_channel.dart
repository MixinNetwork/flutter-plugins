import 'package:flutter/services.dart';

typedef MessageHandler = Future<dynamic> Function(MethodCall call);

class ClientMessageChannel {
  const ClientMessageChannel();

  static const _channel = MethodChannel('webview_message/client_channel');

  Future<dynamic> invokeMethod(String method, [dynamic arguments]) {
    return _channel.invokeMethod(method, arguments);
  }

  static final Set<MessageHandler> _handlers = {};

  void setMessageHandler(MessageHandler? handler) {
    _handlers.clear();
    if (handler != null) _handlers.add(handler);
    _installDispatcher();
  }

  void addMessageHandler(MessageHandler handler) {
    _handlers.add(handler);
    _installDispatcher();
  }

  void removeMessageHandler(MessageHandler handler) {
    _handlers.remove(handler);
  }

  void _installDispatcher() {
    _channel.setMethodCallHandler((call) async {
      for (final handler in List<MessageHandler>.of(_handlers)) {
        if (_handlers.contains(handler)) await handler(call);
      }
    });
  }
}
