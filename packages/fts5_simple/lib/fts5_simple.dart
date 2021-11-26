// ignore_for_file: camel_case_types
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';

final _Binding binding = _Binding(open.openSqlite());

extension Sqlite3FtsExtension on Database {
  void loadExtesnion(String zFile) {
    // FIXME https://www.sqlite.org/c3ref/enable_load_extension.html
    binding.sqlite3EnableLoadExtension(handle.cast(), 1);

    final errorOut = malloc<Pointer<Utf8>>();
    final ret = binding.sqlite3LoadExtension(
        handle.cast(), zFile.toNativeUtf8(), nullptr, errorOut);
    try {
      if (ret != 0) {
        throw Exception(
            'Error loading extension($ret): ${errorOut.value.toDartString()}');
      }
    } finally {
      malloc.free(errorOut);
    }

    binding.sqlite3EnableLoadExtension(handle.cast(), 0);
  }

  void loadSimpleExtension() {
    final dir = p.dirname(Platform.resolvedExecutable);
    final String simpleLibPath;
    String dictPath;
    if (Platform.isWindows) {
      simpleLibPath = p.join(dir, 'simple.dll');
      // data\flutter_assets\packages\fts5_simple\dicts
      dictPath = p.join(
          dir, 'data', 'flutter_assets', 'packages', 'fts5_simple', 'dicts');
    } else if (Platform.isMacOS) {
      simpleLibPath = 'libsimple';
      // ../Frameworks/App.framework/Resources/flutter_assets/packages/fts5_simple/dicts
      dictPath = p.join(dir, '..', 'Frameworks', 'App.framework', 'Resources',
          'flutter_assets', 'packages', 'fts5_simple');
      dictPath = p.join(dictPath, 'dicts');
    } else {
      throw UnimplementedError('Not implemented');
    }

    debugPrint('simpleLibPath: $simpleLibPath');
    debugPrint('dictPath: $dictPath');

    loadExtesnion(simpleLibPath);

    final exist = Directory(dictPath).existsSync();
    assert(exist, 'dictPath($dictPath) does not exist');
    if (!exist) {
      return;
    }
    select('select jieba_dict(?)', [dictPath]);
  }
}

typedef _sqlite3_load_extension_native = Int32 Function(Pointer<Void> db,
    Pointer<Utf8> zFile, Pointer<Utf8> zProc, Pointer<Pointer<Utf8>> pzErrMsg);
typedef _sqlite3_load_extension_dart = int Function(Pointer<Void> db,
    Pointer<Utf8> zFile, Pointer<Utf8> zProc, Pointer<Pointer<Utf8>> pzErrMsg);

typedef _sqlite3_enable_load_extension_native = Int32 Function(
    Pointer<Void> db, Int32 onoff);
typedef _sqlite3_enable_load_extension_dart = int Function(
    Pointer<Void> db, int onoff);

class _Binding {
  _Binding(this.library)
      : sqlite3LoadExtension = library.lookupFunction<
            _sqlite3_load_extension_native,
            _sqlite3_load_extension_dart>("sqlite3_load_extension"),
        sqlite3EnableLoadExtension = library.lookupFunction<
                _sqlite3_enable_load_extension_native,
                _sqlite3_enable_load_extension_dart>(
            "sqlite3_enable_load_extension");

  final DynamicLibrary library;

  final _sqlite3_load_extension_dart sqlite3LoadExtension;
  final _sqlite3_enable_load_extension_dart sqlite3EnableLoadExtension;
}
