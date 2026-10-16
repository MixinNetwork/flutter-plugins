import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'bridge_bindings.g.dart';

// The codec only describes bytes. All transport and replies use FFI/Dart ports.
class NativeTransport {
  NativeTransport._() {
    final library = Platform.isWindows
        ? DynamicLibrary.open('desktop_drop_plugin.dll')
        : Platform.isLinux
        ? DynamicLibrary.open('libdesktop_drop_plugin.so')
        : Platform.isAndroid
        ? DynamicLibrary.open('libdesktop_drop_ffi.so')
        : DynamicLibrary.process();
    bindings = DropBridgeBindings(library);
    _port.listen(_receive);
    context = bindings.dd_rpc_open(
      ui.PlatformDispatcher.instance.engineId ?? 0,
      NativeApi.initializeApiDLData,
      _port.sendPort.nativePort,
    );
    if (context == 0) {
      _port.close();
      throw StateError('desktop_drop could not connect to this Flutter engine');
    }
  }

  @visibleForTesting
  NativeTransport.testing();
  @visibleForTesting
  static NativeTransport? debugOverride;
  @visibleForTesting
  Future<Object?> Function(MethodCall)? invokeHandler;

  static NativeTransport get instance => debugOverride ?? _native;
  static final _native = NativeTransport._();
  static const _codec = StandardMethodCodec();
  late final DropBridgeBindings bindings;
  late final int context;
  late final _port = ReceivePort();
  final _pending = <int, Completer<Object?>>{};
  int _request = 0;
  bool _closed = false;
  Future<Object?> Function(MethodCall)? onEvent;

  T _withBytes<T>(ByteData bytes, T Function(Pointer<Uint8>, int) action) {
    final pointer = bindings.dd_alloc(bytes.lengthInBytes);
    if (pointer == nullptr && bytes.lengthInBytes != 0) {
      throw StateError('Cannot allocate desktop_drop message');
    }
    try {
      pointer
          .asTypedList(bytes.lengthInBytes)
          .setAll(
            0,
            bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          );
      return action(pointer, bytes.lengthInBytes);
    } finally {
      bindings.dd_free(pointer);
    }
  }

  Future<T?> invoke<T>(String method, [Object? arguments]) async {
    final mock = invokeHandler;
    if (mock != null) return await mock(MethodCall(method, arguments)) as T?;
    if (_closed) throw PlatformException(code: 'source_expired');
    final request = ++_request;
    final result = Completer<Object?>();
    _pending[request] = result;
    try {
      _withBytes(
        _codec.encodeMethodCall(MethodCall(method, arguments)),
        (pointer, length) =>
            bindings.dd_rpc_call(context, request, pointer, length),
      );
      return await result.future as T?;
    } finally {
      _pending.remove(request);
    }
  }

  Future<void> _receive(dynamic message) async {
    final data = message as List;
    final request = data[1] as int;
    final bytes = ByteData.sublistView(data[2] as Uint8List);
    if (data[0] == 2) {
      _closed = true;
      for (final pending in _pending.values) {
        if (!pending.isCompleted) {
          pending.completeError(PlatformException(code: 'source_expired'));
        }
      }
      _port.close();
      return;
    }
    if (data[0] == 1) {
      final pending = _pending[request];
      if (pending == null) return;
      try {
        if (bytes.lengthInBytes == 0) throw MissingPluginException();
        pending.complete(_codec.decodeEnvelope(bytes));
      } catch (error, stack) {
        pending.completeError(error, stack);
      }
      return;
    }
    ByteData reply;
    try {
      final handler = onEvent;
      final call = _codec.decodeMethodCall(bytes);
      final value = handler == null ? false : await handler(call);
      if (request == 0) return;
      reply = _codec.encodeSuccessEnvelope(value);
    } on PlatformException catch (error) {
      reply = _codec.encodeErrorEnvelope(
        code: error.code,
        message: error.message,
        details: error.details,
      );
    } catch (error) {
      reply = _codec.encodeErrorEnvelope(
        code: 'drop_failed',
        message: '$error',
      );
    }
    if (request == 0 || _closed) return;
    _withBytes(
      reply,
      (pointer, length) =>
          bindings.dd_rpc_complete(context, request, pointer, length),
    );
  }
}
