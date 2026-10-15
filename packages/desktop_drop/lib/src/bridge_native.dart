import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'bridge.dart';
import 'bridge_bindings.g.dart';
import 'drop_offer.dart';

const _channel = MethodChannel('desktop_drop');
final _connections = <int, _NativeBridge>{};
bool _handlerInstalled = false;

DropBridge createDropBridge(
  int view,
  DropDecision decide,
  DropPlatformEvent event,
) {
  if (!_handlerInstalled) {
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      final map = (call.arguments as Map).cast<Object?, Object?>();
      final connection = _connections[map['view']];
      if (connection == null || connection._disposed) return 0;
      if (call.method == 'query') {
        if ((map['generation'] as int? ?? 0) != connection.generation) return 0;
        return connection._decideMap(map['offer'] as Map, map);
      }
      if (call.method == 'feedback' ||
          call.method == 'drop' ||
          call.method == 'exit') {
        if ((map['generation'] as int? ?? 0) != connection.generation) return 0;
        connection.event({...map, 'event': call.method});
        return null;
      }
      throw MissingPluginException('Unknown desktop_drop event ${call.method}');
    });
  }
  final bridge = _NativeBridge(view, decide, event);
  _connections[view] = bridge;
  return bridge;
}

class _NativeBridge implements DropBridge {
  _NativeBridge(this.view, this.decide, this.event);
  final int view;
  final DropDecision decide;
  final DropPlatformEvent event;
  bool _disposed = false;
  int _context = 0;
  @override
  int generation = 0;
  ReceivePort? _port;
  NativeCallable<DDDecideFunction>? _callback;
  DropBridgeBindings? _bindings;

  int _safeDecision(String json, double x, double y) {
    try {
      return decide(
        view,
        DropOffer.fromMap(jsonDecode(json) as Map),
        Offset(x, y),
      );
    } catch (error, stack) {
      _report(error, stack);
      return 0;
    }
  }

  int _decideMap(Map offer, Map event) {
    try {
      return decide(
        view,
        DropOffer.fromMap(offer),
        Offset((event['x'] as num).toDouble(), (event['y'] as num).toDouble()),
      );
    } catch (error, stack) {
      _report(error, stack);
      return 0;
    }
  }

  @override
  Future<void> initialize() async {
    final descriptor = await _channel.invokeMapMethod<Object?, Object?>(
      'initialize',
      {'view': view},
    );
    if (_disposed) return;
    if (descriptor == null || descriptor['view'] != view) {
      throw StateError('desktop_drop could not bind Flutter view $view');
    }
    // GTK and Android can request a synchronous Dart predicate through an
    // asynchronous method-channel reply. They do not block their main loop.
    if (!descriptor.containsKey('context')) {
      generation = descriptor['generation'] as int? ?? 0;
      return;
    }
    _context = descriptor['context'] as int;
    _bindings = DropBridgeBindings.fromLookup(<T extends NativeType>(
      String name,
    ) {
      final key = switch (name) {
        'dd_bridge_register' => 'register',
        'dd_bridge_complete' => 'complete',
        'dd_bridge_unregister' => 'unregister',
        _ => throw ArgumentError.value(name, 'name', 'Unknown bridge symbol'),
      };
      return Pointer<T>.fromAddress(descriptor[key] as int);
    });
    _callback = NativeCallable<DDDecideFunction>.isolateLocal((
      Pointer<DDRequest> pointer,
    ) {
      final request = pointer.ref;
      if (_disposed || request.generation != generation) return 0;
      return _safeDecision(
        utf8.decode(request.payload.cast<Uint8>().asTypedList(request.length)),
        request.x,
        request.y,
      );
    }, exceptionalReturn: 0);
    _port = ReceivePort()
      ..listen((dynamic message) {
        final data = message as List;
        if (_disposed || data[0] != _context || data[1] != generation) return;
        final target = _safeDecision(
          data[8] as String,
          (data[6] as num).toDouble(),
          (data[7] as num).toDouble(),
        );
        _bindings!.dd_bridge_complete(
          _context,
          generation,
          data[2] as int,
          target,
        );
      });
    generation = _bindings!.dd_bridge_register(
      _context,
      NativeApi.initializeApiDLData,
      _port!.sendPort.nativePort,
      _callback!.nativeFunction,
      ui.isRunningOnPlatformThread ? 1 : 0,
      view,
    );
    if (generation == 0) {
      dispose();
      throw StateError(
        'desktop_drop could not initialize the native Dart bridge',
      );
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (identical(_connections[view], this)) _connections.remove(view);
    if (generation != 0) _bindings?.dd_bridge_unregister(_context, generation);
    _port?.close();
    _callback?.close();
  }
}

void _report(Object error, StackTrace stack) {
  scheduleMicrotask(
    () => FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'desktop_drop',
        context: ErrorDescription(
          'while deciding whether to accept an OS drop',
        ),
      ),
    ),
  );
}
