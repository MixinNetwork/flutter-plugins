import 'dart:io';

import 'package:flutter/painting.dart';

ImageProvider<Object>? resolveMarkdownLocalImageProvider(String source) {
  final trimmed = source.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  final uri = Uri.tryParse(trimmed);
  if (uri != null) {
    if (uri.scheme == 'file') {
      return FileImage(File.fromUri(uri));
    }
    if (uri.scheme.isNotEmpty) {
      return null;
    }
  }

  final file = File(trimmed);
  if (file.isAbsolute || file.existsSync()) {
    return FileImage(file);
  }

  return null;
}
