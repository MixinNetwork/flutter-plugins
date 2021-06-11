import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DesktopLifecycle {
  static const MethodChannel _channel = MethodChannel('desktop_lifecycle');

  static DesktopLifecycle? _instance;

  static DesktopLifecycle get instance {
    if (_instance == null) {
      _instance = DesktopLifecycle._();
      _channel.setMethodCallHandler(_instance!.handleMethodCall);
      _channel.invokeMethod("init");
    }
    return _instance!;
  }

  DesktopLifecycle._();

  final ValueNotifier<bool> _activeState = ValueNotifier(true);

  ValueListenable<bool> get isActive {
    return _activeState;
  }

  Future<dynamic> handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case "onApplicationFocusChanged":
        _onApplicationFocusChange(call.arguments as bool);
        break;
      default:
        break;
    }
  }

  void _onApplicationFocusChange(bool active) {
    _activeState.value = active;
  }
}
