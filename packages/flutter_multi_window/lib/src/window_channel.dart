import 'package:flutter/services.dart';

const MethodChannel miltiWindowChannel =
    MethodChannel('mixin.one/flutter_multi_window');

typedef MessageHandler = Future<dynamic> Function(MethodCall call);

class ClientMessageChannel {
  const ClientMessageChannel();

  static const _channel = MethodChannel(
    'mixin.one/multi_window_client_channel',
  );

  Future<dynamic> invokeMethod(String method, [dynamic arguments]) {
    return _channel.invokeMethod(method, arguments);
  }

  void setMessageHandler(MessageHandler? handler) {
    _channel.setMethodCallHandler(handler);
  }
}
