
import 'dart:async';

import 'package:flutter/services.dart';

class MultiWindowWindows {
  static const MethodChannel _channel = MethodChannel('multi_window_windows');

  static Future<String?> get platformVersion async {
    final String? version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }
}
