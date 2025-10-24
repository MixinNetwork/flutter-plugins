import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef MethodCallHandler = Future<dynamic> Function(MethodCall call);

class WindowMethodChannel {
  final String name;

  const WindowMethodChannel(this.name);

  @optionalTypeArgs
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) {
    _initializeChannelManager();
    return _invokeMethodOnChannel<T>(name, method, arguments);
  }

  Future<void> setMethodCallHandler(
      Future<dynamic> Function(MethodCall call)? handler) async {
    _initializeChannelManager();

    if (handler != null) {
      if (_registeredHandlers.containsKey(name)) {
        _registeredHandlers[name] = handler;
        return;
      }
      _registeredHandlers[name] = handler;
      await _registerMethodHandler(name);
    } else {
      if (!_registeredHandlers.containsKey(name)) {
        return;
      }
      await _unregisterMethodHandler(name);
      _registeredHandlers.remove(name);
    }
  }
}

final _registeredHandlers = <String, MethodCallHandler>{};

const _methodChannel = MethodChannel('mixin.one/desktop_multi_window/channels');

bool _initialized = false;

void _initializeChannelManager() {
  if (_initialized) {
    return;
  }
  _initialized = true;
  _methodChannel.setMethodCallHandler((call) async {
    if (call.method == 'methodCall') {
      final arguments = call.arguments as Map;
      final channelName = arguments['channel'] as String;
      final method = arguments['method'] as String;
      final args = arguments['arguments'];
      final handler = _registeredHandlers[channelName];
      if (handler != null) {
        final methodCall = MethodCall(method, args);
        return handler.call(methodCall);
      } else {
        throw Exception(
            'No method call handler registered for channel $channelName');
      }
    } else {
      throw MissingPluginException('No handler for method ${call.method}');
    }
  });
}

Future<void> _registerMethodHandler(String name) async {
  await _methodChannel.invokeMethod('registerMethodHandler', {
    'channel': name,
  });
}

Future<void> _unregisterMethodHandler(String name) async {
  await _methodChannel.invokeMethod('unregisterMethodHandler', {
    'channel': name,
  });
}

Future<T?> _invokeMethodOnChannel<T>(
    String name, String method, dynamic arguments) {
  return _methodChannel.invokeMethod<T>('invokeMethod', {
    'channel': name,
    'method': method,
    'arguments': arguments,
  });
}
