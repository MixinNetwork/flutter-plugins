import 'dart:ui';

import 'package:flutter/services.dart';

import 'window_channel.dart';
import 'window_controller.dart';

class WindowControllerMainImpl extends WindowController {
  final MethodChannel _channel = miltiWindowChannel;

  // the id of this window
  final int _id;

  final bool _isInMainIsolate;

  final _windowChannel = const ClientMessageChannel();

  WindowControllerMainImpl(
    this._id,
    this._isInMainIsolate,
  );

  @override
  Future<void> close() {
    return _channel.invokeMethod('close', _id);
  }

  @override
  Future<void> hide() {
    return _channel.invokeMethod('hide', _id);
  }

  @override
  Future<void> show() {
    return _channel.invokeMethod('show', _id);
  }

  @override
  Future<void> center() {
    return _channel.invokeMethod('center', _id);
  }

  @override
  Future<void> setFrame(Rect frame) {
    return _channel.invokeMethod('setFrame', <String, dynamic>{
      'windowId': _id,
      'left': frame.left,
      'top': frame.top,
      'width': frame.width,
      'height': frame.height,
    });
  }

  @override
  Future<void> setTitle(String title) {
    return _channel.invokeMethod('setTitle', <String, dynamic>{
      'windowId': _id,
      'title': title,
    });
  }

  @override
  void invokeMethod(String method, [arguments]) {
    _windowChannel.invokeMethod('invoke', <String, dynamic>{
      'windowId': _isInMainIsolate ? 0 : _id,
      'arguments': arguments,
      'method': method,
    });
  }

  @override
  void setMethodHandler(void Function(MethodCall call) handler) {
    _windowChannel.setMessageHandler((call) async {
      final windowId = call.arguments['windowId'];
      if (_isInMainIsolate ? windowId == 0 : windowId == _id) {
        final arguments = call.arguments['arguments'];
        final method = call.arguments['method'] as String;
        handler(MethodCall(method, arguments));
      }
    });
  }

  @override
  Future<void> setFrameAutosaveName(String name) {
    return _channel.invokeMethod('setFrameAutosaveName', <String, dynamic>{
      'windowId': _id,
      'name': name,
    });
  }
}
