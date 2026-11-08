import 'dart:ffi';
import 'dart:io';
import 'dart:ui' show TextRange;

import 'package:ffi/ffi.dart';

import 'core_foundation.dart';
import 'icu.dart';

/// Segments [length] UTF-16 code units at [units].
typedef NativeWordBoundaries = List<TextRange>? Function(
  Pointer<Uint16> units,
  int length,
);

final NativeWordBoundaries? _native =
    Platform.isMacOS || Platform.isIOS ? loadCoreFoundation() : loadIcu();

List<TextRange>? platformWordBoundaries(String text) {
  final native = _native;
  if (native == null) {
    return null;
  }
  if (text.isEmpty) {
    return const [];
  }
  return using((arena) {
    final units = arena<Uint16>(text.length);
    units.asTypedList(text.length).setAll(0, text.codeUnits);
    return native(units, text.length);
  });
}
