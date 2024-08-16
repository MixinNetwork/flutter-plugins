import 'dart:ffi';
import 'dart:ui';

import 'package:ffi/ffi.dart';
import 'package:objective_c/objective_c.dart' as objc;

import 'src/data_detector_bindings_generated.dart' as binding;

export 'src/data_detector_bindings_generated.dart'
    show NSTextCheckingType, NSMatchingOptions;

extension on TextRange {
  Pointer<binding.NSRange> toNSRange() {
    final range = malloc.allocate<binding.NSRange>(sizeOf<binding.NSRange>());
    range.ref.location = start;
    range.ref.length = end - start;
    return range;
  }
}

class TextCheckingResult {
  TextCheckingResult._(this._inner);

  final binding.NSTextCheckingResult _inner;

  binding.NSTextCheckingType get type => _inner.resultType;

  TextRange get range {
    final msgSend = objc.msgSendPointer
        .cast<
            NativeFunction<
                binding.NSRange Function(
                    Pointer<objc.ObjCObject>, Pointer<objc.ObjCSelector>)>>()
        .asFunction<
            binding.NSRange Function(
                Pointer<objc.ObjCObject>, Pointer<objc.ObjCSelector>)>();
    final property = objc.registerName("range");

    // the generated _inner.getRange() not working on macos x64, call send manually
    final range = msgSend(_inner.pointer, property);
    final textRange =
        TextRange(start: range.location, end: range.location + range.length);
    return textRange;
  }

  DateTime? get date {
    final timestamp = _inner.date?.timeIntervalSince1970;
    if (timestamp == null) {
      return null;
    }
    return DateTime.fromMicrosecondsSinceEpoch((timestamp * 1e6) as int);
  }

  Duration get duration =>
      Duration(microseconds: (_inner.duration * 1e6) as int);

  Uri? get url {
    final url = _inner.URL?.absoluteString;
    if (url == null) {
      return null;
    }
    return Uri.parse(url.toString());
  }
}

class DataDetector {
  factory DataDetector(binding.NSTextCheckingType type) {
    final error = malloc
        .allocate<Pointer<objc.ObjCObject>>(sizeOf<Pointer<objc.ObjCObject>>());
    final detector =
        binding.NSDataDetector.alloc().initWithTypes_error_(type.value, error);
    if (error.value != nullptr) {
      final err = objc.NSError.castFromPointer(error.value);
      throw err;
    }
    return DataDetector._(detector!);
  }

  DataDetector._(this._detector);

  final binding.NSDataDetector _detector;

  List<TextCheckingResult> matchesInString(
    String str, {
    binding.NSMatchingOptions? options,
    TextRange? range,
  }) {
    final nsRange = (range ?? TextRange(start: 0, end: str.length)).toNSRange();
    final array = _detector.matchesInString_options_range_(
        str.toNSString(),
        options ?? binding.NSMatchingOptions.NSMatchingReportCompletion,
        nsRange.ref);
    malloc.free(nsRange);

    final results = <TextCheckingResult>[];
    for (var i = 0; i < array.count; i++) {
      final result =
          binding.NSTextCheckingResult.castFrom(array.objectAtIndex_(i));
      results.add(TextCheckingResult._(result));
    }
    return results;
  }
}
