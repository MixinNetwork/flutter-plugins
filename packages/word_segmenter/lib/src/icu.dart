import 'dart:ffi';
import 'dart:io';
import 'dart:ui' show TextRange;

import 'package:ffi/ffi.dart';

import 'segmenter_native.dart';

typedef _OpenNative = Pointer<Void> Function(
  Int32 type,
  Pointer<Utf8> locale,
  Pointer<Uint16> text,
  Int32 length,
  Pointer<Int32> status,
);
typedef _Open = Pointer<Void> Function(
  int type,
  Pointer<Utf8> locale,
  Pointer<Uint16> text,
  int length,
  Pointer<Int32> status,
);

const _ubrkWord = 1;
const _ubrkDone = -1;

/// Word boundaries from the system ICU break iterator.
///
/// Flutter's engine ships its own ICU without the CJK dictionary, so this
/// loads the copy that comes with the operating system instead.
NativeWordBoundaries? loadIcu() {
  for (final (name, suffix) in _candidates()) {
    final segmenter = _tryLoad(name, suffix);
    if (segmenter != null) {
      return segmenter;
    }
  }
  return null;
}

/// Library names paired with the symbol suffix their exports use.
Iterable<(String, String)> _candidates() sync* {
  if (Platform.isWindows) {
    // icu.dll since Windows 10 1903, icuuc.dll in 1703 to 1809.
    yield ('icu.dll', '');
    yield ('icuuc.dll', '');
  } else if (Platform.isAndroid) {
    // The NDK's public ICU, API 31+.
    yield ('libicu.so', '');
  } else if (Platform.isLinux) {
    // Distributions build ICU with versioned symbols such as `ubrk_open_74`,
    // and only the development package installs the unversioned soname.
    for (var version = 120; version >= 50; version--) {
      yield ('libicuuc.so.$version', '_$version');
      yield ('libicuuc.so.$version', '');
    }
  }
}

NativeWordBoundaries? _tryLoad(String name, String suffix) {
  final DynamicLibrary library;
  final _Open open;
  final int Function(Pointer<Void>) next;
  final void Function(Pointer<Void>) close;
  try {
    library = DynamicLibrary.open(name);
    open = library.lookupFunction<_OpenNative, _Open>('ubrk_open$suffix');
    next = library.lookupFunction<Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)>('ubrk_next$suffix');
    close = library.lookupFunction<Void Function(Pointer<Void>),
        void Function(Pointer<Void>)>('ubrk_close$suffix');
  } on ArgumentError {
    return null;
  }

  return (units, length) => using((arena) {
        final status = arena<Int32>();
        final iterator = open(_ubrkWord, nullptr, units, length, status);
        // U_FAILURE: error codes are positive, warnings negative.
        if (status.value > 0) {
          return null;
        }
        final segments = <TextRange>[];
        var start = 0;
        for (var end = next(iterator); end != _ubrkDone; end = next(iterator)) {
          segments.add(TextRange(start: start, end: end));
          start = end;
        }
        close(iterator);
        return segments;
      });
}
