import 'package:flutter/services.dart';

typedef MessageHandler = Future<dynamic> Function(MethodCall call);

/// Local titlebar events and commands within the application's Dart isolate.
class TitleBarMessages {
  const TitleBarMessages();

  static final Set<MessageHandler> _handlers = {};

  Future<dynamic> invokeMethod(String method, [dynamic arguments]) async {
    final call = MethodCall(method, arguments);
    for (final handler in List<MessageHandler>.of(_handlers)) {
      if (_handlers.contains(handler)) await handler(call);
    }
  }

  void setMessageHandler(MessageHandler? handler) {
    _handlers.clear();
    if (handler != null) _handlers.add(handler);
  }

  void addMessageHandler(MessageHandler handler) => _handlers.add(handler);

  void removeMessageHandler(MessageHandler handler) =>
      _handlers.remove(handler);
}
