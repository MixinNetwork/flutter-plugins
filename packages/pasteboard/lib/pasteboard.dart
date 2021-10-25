import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

class Pasteboard {
  static const MethodChannel _channel = MethodChannel('pasteboard');

  static Future<Uint8List?> get image async {
    final image = await _channel.invokeMethod('image');

    if (image == null) {
      return null;
    }
    if (Platform.isMacOS) {
      return image as Uint8List;
    } else if (Platform.isWindows) {
      final file = File(image as String);
      final bytes = await file.readAsBytes();
      await file.delete();
      return bytes;
    }
    return null;
  }

  static Future<String?> get absoluteUrlString =>
      _channel.invokeMethod<String?>('absoluteUrlString');

  static Future<Uri?> get uri async {
    final urlString = await absoluteUrlString;
    if (urlString == null) return null;
    return Uri.tryParse(urlString);
  }

  static Future<bool> writeUrl(String url) async =>
      await _channel.invokeMethod('writeUrl', [url]);

  static Future<List<String>> files() async {
    final files = await _channel.invokeMethod<List>('files');
    return files?.cast<String>() ?? const [];
  }
}
