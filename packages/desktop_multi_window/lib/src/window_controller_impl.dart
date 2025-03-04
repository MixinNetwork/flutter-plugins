import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'channels.dart';
import 'window_controller.dart';
import 'window_events.dart';

class WindowControllerImpl extends WindowController {
  final MethodChannel _channel = multiWindowChannel;

  // the id of this window
  final int _id;

  WindowControllerImpl(this._id) {
    windowEventsChannel.setMethodCallHandler(_methodCallHandler);
  }

  final ObserverList<WindowEvents> _listeners = ObserverList<WindowEvents>();

  Future<void> _methodCallHandler(MethodCall call) async {
    for (final WindowEvents listener in listeners) {
      if (!_listeners.contains(listener)) {
        return;
      }

      if (call.method != 'onEvent') throw UnimplementedError();

      String eventName = call.arguments['eventName'];
      listener.onWindowEvent(eventName);
      Map<String, Function> funcMap = {
        kWindowEventClose: listener.onWindowClose,
        kWindowEventFocus: listener.onWindowFocus,
        kWindowEventBlur: listener.onWindowBlur,
        kWindowEventMaximize: listener.onWindowMaximize,
        kWindowEventUnmaximize: listener.onWindowUnmaximize,
        kWindowEventMinimize: listener.onWindowMinimize,
        kWindowEventRestore: listener.onWindowRestore,
        kWindowEventResize: listener.onWindowResize,
        kWindowEventResized: listener.onWindowResized,
        kWindowEventMove: listener.onWindowMove,
        kWindowEventMoved: listener.onWindowMoved,
        kWindowEventEnterFullScreen: listener.onWindowEnterFullScreen,
        kWindowEventLeaveFullScreen: listener.onWindowLeaveFullScreen,
        kWindowEventDocked: listener.onWindowDocked,
        kWindowEventUndocked: listener.onWindowUndocked,
      };
      funcMap[eventName]?.call();
    }
  }

  List<WindowEvents> get listeners {
    final List<WindowEvents> localListeners = List<WindowEvents>.from(_listeners);
    return localListeners;
  }

  bool get hasListeners {
    return _listeners.isNotEmpty;
  }

  @override
  void addListener(WindowEvents listener) {
    _listeners.add(listener);
  }

  @override
  void removeListener(WindowEvents listener) {
    _listeners.remove(listener);
  }

  double getDevicePixelRatio() {
    // Subsequent version, remove this deprecated member.
    // ignore: deprecated_member_use
    return window.devicePixelRatio;
  }

  @override
  int get windowId => _id;

  @override
  Future<void> close() {
    return _channel.invokeMethod('close', {'windowId': _id});
  }

  @override
  Future<void> hide() {
    return _channel.invokeMethod('hide', {'windowId': _id});
  }

  @override
  Future<void> show() {
    return _channel.invokeMethod('show', {'windowId': _id});
  }

  @override
  Future<void> center() {
    return _channel.invokeMethod('center', {'windowId': _id});
  }

  @override
  Future<Rect> getFrame() async {
    final Map<String, dynamic> arguments = {
      'windowId': _id,
      'devicePixelRatio': getDevicePixelRatio(),
    };
    final Map<dynamic, dynamic> resultData = await _channel.invokeMethod(
      'getFrame',
      arguments,
    );

    return Rect.fromLTWH(
      resultData['left'],
      resultData['top'],
      resultData['width'],
      resultData['height'],
    );
  }

  @override
  Future<void> setFrame(Rect frame, {bool animate = false}) {
    return _channel.invokeMethod('setFrame', <String, dynamic>{
      'windowId': _id,
      'left': frame.left,
      'top': frame.top,
      'width': frame.width,
      'height': frame.height,
      'animate': animate,
    });
  }

  @override
  Future<Size> getSize() async {
    final Rect frame = await getFrame();
    return frame.size;
  }

  @override
  Future<void> setSize(Size size, {bool animate = false}) {
    return _channel.invokeMethod('setFrame', <String, dynamic>{
      'windowId': _id,
      'width': size.width,
      'height': size.height,
      'animate': animate,
    });
  }

  @override
  Future<Offset> getPosition() async {
    final Rect frame = await getFrame();
    return frame.topLeft;
  }

  @override
  Future<void> setPosition(Offset position, {bool animate = false}) {
    return _channel.invokeMethod('setFrame', <String, dynamic>{
      'windowId': _id,
      'left': position.dx,
      'top': position.dy,
      'animate': animate,
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
  Future<void> resizable(bool resizable) {
    if (Platform.isMacOS) {
      return _channel.invokeMethod('resizable', <String, dynamic>{
        'windowId': _id,
        'resizable': resizable,
      });
    } else {
      throw MissingPluginException(
        'This functionality is only available on macOS',
      );
    }
  }

  @override
  Future<void> setFrameAutosaveName(String name) {
    return _channel.invokeMethod('setFrameAutosaveName', <String, dynamic>{
      'windowId': _id,
      'name': name,
    });
  }
}
