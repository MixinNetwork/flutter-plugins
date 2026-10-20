import 'dart:ffi';
import 'dart:ui' show TextRange;

import 'segmenter_native.dart';

final class _CFRange extends Struct {
  @Long()
  external int location;

  @Long()
  external int length;
}

typedef _CreateStringNative = Pointer<Void> Function(
  Pointer<Void> allocator,
  Pointer<Uint16> chars,
  Long length,
);
typedef _CreateString = Pointer<Void> Function(
  Pointer<Void> allocator,
  Pointer<Uint16> chars,
  int length,
);
typedef _CreateTokenizerNative = Pointer<Void> Function(
  Pointer<Void> allocator,
  Pointer<Void> string,
  _CFRange range,
  UnsignedLong options,
  Pointer<Void> locale,
);
typedef _CreateTokenizer = Pointer<Void> Function(
  Pointer<Void> allocator,
  Pointer<Void> string,
  _CFRange range,
  int options,
  Pointer<Void> locale,
);

const _kCFStringTokenizerUnitWordBoundary = 4;
const _kCFStringTokenizerTokenNone = 0;

/// Word boundaries from `CFStringTokenizer`, the segmenter behind native text
/// views on Apple platforms.
NativeWordBoundaries? loadCoreFoundation() {
  final _CreateString createString;
  final _CreateTokenizer createTokenizer;
  final int Function(Pointer<Void>) advance;
  final _CFRange Function(Pointer<Void>) currentRange;
  final void Function(Pointer<Void>) release;
  try {
    final library = DynamicLibrary.process();
    createString = library.lookupFunction<_CreateStringNative, _CreateString>(
        'CFStringCreateWithCharacters');
    createTokenizer =
        library.lookupFunction<_CreateTokenizerNative, _CreateTokenizer>(
            'CFStringTokenizerCreate');
    advance = library.lookupFunction<UnsignedLong Function(Pointer<Void>),
        int Function(Pointer<Void>)>('CFStringTokenizerAdvanceToNextToken');
    currentRange = library.lookupFunction<
        _CFRange Function(Pointer<Void>),
        _CFRange Function(
            Pointer<Void>)>('CFStringTokenizerGetCurrentTokenRange');
    release = library.lookupFunction<Void Function(Pointer<Void>),
        void Function(Pointer<Void>)>('CFRelease');
  } on ArgumentError {
    return null;
  }

  return (units, length) {
    final string = createString(nullptr, units, length);
    if (string == nullptr) {
      return null;
    }
    final range = Struct.create<_CFRange>()
      ..location = 0
      ..length = length;
    final tokenizer = createTokenizer(
      nullptr,
      string,
      range,
      _kCFStringTokenizerUnitWordBoundary,
      nullptr,
    );
    final segments = <TextRange>[];
    while (advance(tokenizer) != _kCFStringTokenizerTokenNone) {
      final token = currentRange(tokenizer);
      segments.add(
        TextRange(start: token.location, end: token.location + token.length),
      );
    }
    release(tokenizer);
    release(string);
    return segments;
  };
}
