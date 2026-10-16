import 'package:flutter/services.dart';

class NativeTransport {
  static final instance = NativeTransport();
  Future<T?> invoke<T>(String method, [Object? arguments]) =>
      Future.error(MissingPluginException('desktop_drop: $method'));
}
