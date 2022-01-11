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
  Future<void> setPosition(Offset position) {
    return _channel.invokeMethod('setPosition', <String, dynamic>{
      'windowId': _id,
      'x': position.dx,
      'y': position.dy,
    });
  }

  @override
  Future<void> setSize(Size size) {
    return _channel.invokeMethod('setSize', <String, dynamic>{
      'windowId': _id,
      'width': size.width,
      'height': size.height,
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

  @override
  void startDragging() {
    _channel.invokeMethod('startDragging', <String, dynamic>{
      'windowId': _id,
    });
  }

  @override
  Future<void> setMaxSize(Size size) {
    return _channel.invokeMethod('setMaxSize', <String, dynamic>{
      'windowId': _id,
      'width': size.width,
      'height': size.height,
    });
  }

  @override
  Future<void> setMinSize(Size size) {
    return _channel.invokeMethod('setMinSize', <String, dynamic>{
      'windowId': _id,
      'width': size.width,
      'height': size.height,
    });
  }
}
