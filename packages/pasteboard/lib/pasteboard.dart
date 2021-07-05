import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

class Pasteboard {
  static const MethodChannel _channel = MethodChannel('pasteboard');

  static Future<Uint8List?> get image =>
      _channel.invokeMethod<Uint8List?>('image');

  static Future<String?> get absoluteUrlString =>
      _channel.invokeMethod<String?>('absoluteUrlString');

  static Future<Uri?> get uri async {
    final urlString = await absoluteUrlString;
    if (urlString == null) return null;
    return Uri.tryParse(urlString);
  }

  static Future<bool> writeUrl(String url) async =>
      await _channel.invokeMethod('writeUrl', [url]);
}
