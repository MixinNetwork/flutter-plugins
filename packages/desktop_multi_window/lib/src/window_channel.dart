import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef MethodCallHandler = Future<dynamic> Function(MethodCall call);

/// Channel communication mode
enum ChannelMode {
  /// Unidirectional mode: All engines can invoke this channel
  /// Only one engine can register as handler
  unidirectional('unidirectional'),

  /// Bidirectional mode: Only paired engines can invoke each other
  /// Maximum of 2 engines can register, and only they can call each other
  bidirectional('bidirectional');

  final String value;
  const ChannelMode(this.value);
}

/// Exception thrown when a window channel operation fails.
class WindowChannelException implements Exception {
  final String code;
  final String message;
  final dynamic details;

  WindowChannelException(this.code, this.message, [this.details]);

  @override
  String toString() {
    if (details != null) {
      return 'WindowChannelException($code, $message, $details)';
    }
    return 'WindowChannelException($code, $message)';
  }
}

/// A method channel for cross-window communication.
///
/// Supports two modes:
/// - [ChannelMode.unidirectional]: One engine registers as handler, all engines can invoke
/// - [ChannelMode.bidirectional]: Two engines form a pair and can only invoke each other
class WindowMethodChannel {
  final String name;
  final ChannelMode mode;

  const WindowMethodChannel(
    this.name, {
    this.mode = ChannelMode.bidirectional,
  });

  /// Invokes a method on the target engine that has registered this channel.
  ///
  /// For unidirectional channels: Invokes the single registered handler
  /// For bidirectional channels: Invokes the peer engine in the pair
  ///
  /// Throws [WindowChannelException] if:
  /// - The channel is not registered
  /// - The target engine is not available
  /// - For bidirectional: caller is not part of the pair
  @optionalTypeArgs
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) async {
    _initializeChannelManager();
    try {
      return await _invokeMethodOnChannel<T>(name, method, arguments);
    } on PlatformException catch (e) {
      throw WindowChannelException(
        e.code,
        e.message ?? 'Failed to invoke method on channel $name',
        e.details,
      );
    }
  }

  /// Sets the method call handler for this channel.
  ///
  /// The communication mode is determined by the [mode] parameter passed to the constructor:
  /// - [ChannelMode.unidirectional]: Only one engine can register, all can invoke
  /// - [ChannelMode.bidirectional]: Up to 2 engines can register, only they can invoke each other
  ///
  /// Pass `null` as handler to remove the handler and unregister the channel.
  ///
  /// Throws [WindowChannelException] if:
  /// - Registration fails (e.g., channel limit reached)
  /// - Mode conflicts with existing registration
  Future<void> setMethodCallHandler(
    Future<dynamic> Function(MethodCall call)? handler,
  ) async {
    _initializeChannelManager();

    if (handler != null) {
      // Update handler if already registered
      if (_registeredHandlers.containsKey(name)) {
        _registeredHandlers[name] = handler;
        return;
      }

      // Register new handler
      try {
        await _registerMethodHandler(name, mode);
        _registeredHandlers[name] = handler;
      } on PlatformException catch (e) {
        throw WindowChannelException(
          e.code,
          e.message ?? 'Failed to register handler for channel $name',
          e.details,
        );
      }
    } else {
      // Remove handler
      if (!_registeredHandlers.containsKey(name)) {
        return;
      }

      try {
        await _unregisterMethodHandler(name);
        _registeredHandlers.remove(name);
      } on PlatformException catch (e) {
        // Even if unregistration fails, remove the handler locally
        _registeredHandlers.remove(name);
        if (kDebugMode) {
          print(
              'Warning: Failed to unregister handler for channel $name: ${e.message}');
        }
      }
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
      if (handler == null) {
        throw WindowChannelException(
          'NO_HANDLER',
          'No method call handler registered for channel $channelName',
        );
      }

      final methodCall = MethodCall(method, args);
      return await handler.call(methodCall);
    } else {
      throw MissingPluginException('No handler for method ${call.method}');
    }
  });
}

Future<void> _registerMethodHandler(String name, ChannelMode mode) async {
  try {
    await _methodChannel.invokeMethod('registerMethodHandler', {
      'channel': name,
      'mode': mode.value,
    });
  } on PlatformException catch (e) {
    if (e.code == 'CHANNEL_LIMIT_REACHED') {
      throw WindowChannelException(
        e.code,
        mode == ChannelMode.unidirectional
            ? 'Cannot register channel "$name": already registered in unidirectional mode'
            : 'Cannot register channel "$name": maximum of 2 engines allowed per channel',
        e.details,
      );
    } else if (e.code == 'CHANNEL_MODE_CONFLICT') {
      throw WindowChannelException(
        e.code,
        'Cannot register channel "$name": already registered in a different mode',
        e.details,
      );
    }
    rethrow;
  }
}

Future<void> _unregisterMethodHandler(String name) async {
  await _methodChannel.invokeMethod('unregisterMethodHandler', {
    'channel': name,
  });
}

Future<T?> _invokeMethodOnChannel<T>(
    String name, String method, dynamic arguments) async {
  try {
    return await _methodChannel.invokeMethod<T>('invokeMethod', {
      'channel': name,
      'method': method,
      'arguments': arguments,
    });
  } on PlatformException catch (e) {
    if (e.code == 'CHANNEL_UNREGISTERED') {
      throw WindowChannelException(
        e.code,
        'Channel "$name" not accessible (may be unregistered, bidirectional pair, or permission denied)',
        e.details,
      );
    } else if (e.code == 'CHANNEL_NOT_FOUND') {
      throw WindowChannelException(
        e.code,
        'Channel "$name" not found in target engine',
        e.details,
      );
    }
    rethrow;
  }
}
