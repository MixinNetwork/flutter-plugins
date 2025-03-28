import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../desktop_multi_window.dart';
import 'channels.dart';
import 'extensions.dart';

class WindowControllerImpl extends WindowController {
  final MethodChannel _channel = multiWindowChannel;
  final MethodChannel _windowEventsChannel = windowEventsChannel;

  // the id of this window
  final int _id;

  WindowControllerImpl(this._id);

  final ObserverList<WindowEvents> _listeners = ObserverList<WindowEvents>();

  Future<void> _methodCallHandler(MethodCall call) async {
    for (final WindowEvents listener in listeners) {
      if (!_listeners.contains(listener)) {
        return;
      }

      if (call.method != 'onEvent') throw UnimplementedError();

      final String eventName = call.arguments['eventName'];
      final dynamic rawEventData = call.arguments['eventData'];
      final Map<String, dynamic>? eventData =
          rawEventData != null ? Map<String, dynamic>.from(rawEventData as Map) : null;

      listener.onWindowEvent(eventName, eventData);
      Map<String, Function> funcMap = {
        kWindowEventClose: listener.onWindowClose,
        kWindowEventShow: listener.onWindowShow,
        kWindowEventHide: listener.onWindowHide,
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
        kWindowEventMouseMove: (Map<String, dynamic>? eventData) {
          final x = (eventData?['x'] as num?)?.toInt() ?? 0;
          final y = (eventData?['y'] as num?)?.toInt() ?? 0;
          listener.onMouseMove(x, y);
        },
      };
      if (eventData != null) {
        funcMap[eventName]?.call(eventData);
      } else {
        funcMap[eventName]?.call();
      }
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
    if (_listeners.contains(listener)) {
      return;
    }
    _listeners.add(listener);
    if (hasListeners) {
      _windowEventsChannel.setMethodCallHandler(_methodCallHandler);
      _channel.invokeMethod('setHasListeners', <String, dynamic>{
        'windowId': _id,
        'hasListeners': true,
      });
    }
  }

  @override
  void removeListener(WindowEvents listener) {
    if (!_listeners.contains(listener)) {
      return;
    }
    _listeners.remove(listener);
    if (!hasListeners) {
      _windowEventsChannel.setMethodCallHandler(null);
      _channel.invokeMethod('setHasListeners', <String, dynamic>{
        'windowId': _id,
        'hasListeners': false,
      });
    }
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
  Future<void> setFrame(Rect frame, {bool animate = false, double devicePixelRatio = 1.0}) {
    return _channel.invokeMethod('setFrame', <String, dynamic>{
      'windowId': _id,
      'left': frame.left,
      'top': frame.top,
      'width': frame.width,
      'height': frame.height,
      'animate': animate,
      'devicePixelRatio': devicePixelRatio,
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

  @override
  Future<bool> isFocused() async {
    return await _channel.invokeMethod('isFocused', {'windowId': _id});
  }

  @override
  Future<bool> isFullScreen() async {
    return await _channel.invokeMethod('isFullScreen', {'windowId': _id});
  }

  @override
  Future<bool> isMaximized() async {
    return await _channel.invokeMethod('isMaximized', {'windowId': _id});
  }

  @override
  Future<bool> isMinimized() async {
    return await _channel.invokeMethod('isMinimized', {'windowId': _id});
  }

  @override
  Future<bool> isVisible() async {
    return await _channel.invokeMethod('isVisible', {'windowId': _id});
  }

  @override
  Future<void> maximize({bool vertically = false}) async {
    return await _channel.invokeMethod('maximize', {'windowId': _id, 'vertically': vertically});
  }

  @override
  Future<void> unmaximize() async {
    return await _channel.invokeMethod('unmaximize', {'windowId': _id});
  }

  @override
  Future<void> minimize() async {
    return await _channel.invokeMethod('minimize', {'windowId': _id});
  }

  @override
  Future<void> restore() async {
    return await _channel.invokeMethod('restore', {'windowId': _id});
  }

  @override
  Future<void> setFullScreen(bool isFullScreen) async {
    return await _channel.invokeMethod('setFullScreen', {'windowId': _id, 'isFullScreen': isFullScreen});
  }

  @override
  Future<void> setStyle({
    // macOS parameters
    int? styleMask,
    int? collectionBehavior,
    MacOsWindowLevel? level,
    bool? isOpaque,
    bool? hasShadow,
    Color? backgroundColor,
    // Windows parameters
    int? style,
    int? extendedStyle,
  }) async {
    if (Platform.isMacOS) {
      return await _channel.invokeMethod('setStyle', {
        'windowId': _id,
        if (styleMask != null) 'styleMask': styleMask,
        if (collectionBehavior != null) 'collectionBehavior': collectionBehavior,
        if (level != null) 'level': level.value,
        if (isOpaque != null) 'isOpaque': isOpaque,
        if (hasShadow != null) 'hasShadow': hasShadow,
        if (backgroundColor != null) 'backgroundColor': backgroundColor.toJson(),
      });
    } else if (Platform.isWindows) {
      return await _channel.invokeMethod('setStyle', {
        'windowId': _id,
        if (style != null) 'style': style,
        if (extendedStyle != null) 'extendedStyle': extendedStyle,
        if (backgroundColor != null) 'backgroundColor': backgroundColor.toJson(),
      });
    }
  }

  @override
  Future<void> setBackgroundColor(Color backgroundColor) async {
    return await _channel.invokeMethod('setBackgroundColor', {
      'windowId': _id,
      'backgroundColor': backgroundColor.toJson(),
    });
  }

  @override
  Future<void> setIgnoreMouseEvents(bool ignore) async {
    return await _channel.invokeMethod('setIgnoreMouseEvents', {'windowId': _id, 'ignore': ignore});
  }
}
