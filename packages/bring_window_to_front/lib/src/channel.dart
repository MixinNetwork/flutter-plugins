import 'dart:io';

import 'package:flutter/services.dart';

const _methodChannel = MethodChannel('bring_window_to_front');

Future<void> bringToFront() {
  if (!Platform.isLinux) {
    return Future.value();
  }
  return _methodChannel.invokeMethod('bringToFront');
}
