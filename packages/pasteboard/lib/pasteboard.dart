import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class Pasteboard {
  static const MethodChannel _channel = MethodChannel('pasteboard');

  /// Returns the image data of the pasteboard.
  static Future<Uint8List?> get image async {
    final image = await _channel.invokeMethod<Object>('image');

    if (image == null) {
      return null;
    }
    if (Platform.isMacOS || Platform.isLinux || Platform.isIOS) {
      return image as Uint8List;
    } else if (Platform.isWindows) {
      final file = File(image as String);
      final bytes = await file.readAsBytes();
      await file.delete();
      return bytes;
    }
    return null;
  }

  /// only available on Windows
  /// Get "HTML format" from system pasteboard.
  ///  HTML format: https://docs.microsoft.com/en-us/previous-versions/windows/internet-explorer/ie-developer/platform-apis/aa767917(v=vs.85)
  ///
  static Future<String?> get html async {
    if (Platform.isWindows) {
      return await _channel.invokeMethod<Object>('html') as String?;
    }
    return null;
  }

  /// only available on iOS
  ///
  /// set image data to system pasteboard.
  static Future<void> writeImage(Uint8List? image) async {
    if (image == null) {
      return;
    }
    if (Platform.isIOS) {
      await _channel.invokeMethod<void>('writeImage', image);
    }
  }

  /// Only available on desktop platforms.
  ///
  /// Get files from system pasteboard.
  static Future<List<String>> files() async {
    final files = await _channel.invokeMethod<List>('files');
    return files?.cast<String>() ?? const [];
  }

  /// Only available on desktop platforms.
  ///
  /// Set files to system pasteboard.
  static Future<bool> writeFiles(List<String> files) async {
    try {
      await _channel.invokeMethod<Object>('writeFiles', files);
      return true;
    } catch (e) {
      debugPrint('$e');
      return false;
    }
  }
}
