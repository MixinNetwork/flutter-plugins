import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui' show TextRange;

@JS('Intl.Segmenter')
extension type _Segmenter._(JSObject _) implements JSObject {
  external factory _Segmenter(JSArray<JSString> locales, JSObject options);

  external JSObject segment(String input);
}

extension type _SegmentData._(JSObject _) implements JSObject {
  external int get index;

  external String get segment;
}

@JS('Array.from')
external JSArray<_SegmentData> _arrayFrom(JSObject iterable);

final _Segmenter? _segmenter = _createSegmenter();

_Segmenter? _createSegmenter() {
  final intl = globalContext.getProperty<JSObject?>('Intl'.toJS);
  if (intl == null || !intl.has('Segmenter')) {
    return null;
  }
  return _Segmenter(
    JSArray<JSString>(),
    JSObject()..['granularity'] = 'word'.toJS,
  );
}

List<TextRange>? platformWordBoundaries(String text) {
  final segmenter = _segmenter;
  if (segmenter == null) {
    return null;
  }
  return [
    for (final data in _arrayFrom(segmenter.segment(text)).toDart)
      TextRange(start: data.index, end: data.index + data.segment.length),
  ];
}
