import 'dart:ui';

import 'package:flutter/services.dart';

import 'window_controller.dart';

class WindowControllerMainImpl extends WindowController {
  final MethodChannel _channel;
  final int _id;

  WindowControllerMainImpl(this._channel, this._id);

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
}
