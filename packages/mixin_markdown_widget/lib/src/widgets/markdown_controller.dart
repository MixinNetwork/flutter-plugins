import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../clipboard/copy_serializer.dart';
import '../clipboard/plain_text_serializer.dart';
import '../core/document.dart';
import '../debug.dart';
import '../parser/markdown_document_parser.dart';
import '../streaming/streaming_state.dart';

class MarkdownController extends ChangeNotifier {
  /// Creates a controller for [data]. A [document] from [parseDocument] of
  /// the same [data] skips the parse, so an app can parse in an isolate.
  MarkdownController({
    String data = '',
    MarkdownDocument? document,
    MarkdownDocumentParser? parser,
    MarkdownCopySerializer? plainTextSerializer,
  })  : _parser = parser ?? const MarkdownDocumentParser(),
        _plainTextSerializer =
            plainTextSerializer ?? const MarkdownPlainTextSerializer() {
    _replaceData(data, document: document);
  }

  /// Parses [data] as a new controller with the default parser does. It uses
  /// no Flutter bindings, so it can run in an isolate.
  static MarkdownDocument parseDocument(String data) {
    final source = _MarkdownSourceBuffer()..set(data);
    return const MarkdownDocumentParser().parseLines(source.lines, version: 1);
  }

  final MarkdownDocumentParser _parser;
  final MarkdownCopySerializer _plainTextSerializer;
  final ValueNotifier<int> _documentVersionNotifier = ValueNotifier<int>(0);

  MarkdownDocument _document = const MarkdownDocument.empty();
  StreamingMarkdownState _streamingState = const StreamingMarkdownState.empty();
  final _MarkdownSourceBuffer _source = _MarkdownSourceBuffer();
  int _version = 0;
  bool _streamingDraftMode = false;

  MarkdownDocument get document => _document;
  Listenable get documentListenable => _documentVersionNotifier;
  StreamingMarkdownState get streamingState => _streamingState;
  String get data => _source.text;
  String get plainText => _plainTextSerializer.serialize(_document);
  int get version => _version;

  void setData(String data) {
    if (data == _source.text) {
      return;
    }
    _streamingDraftMode = false;
    _replaceData(data);
    notifyListeners();
  }

  void replaceAll(String data) => setData(data);

  void appendChunk(String chunk) {
    if (chunk.isEmpty) {
      return;
    }
    _streamingDraftMode = true;
    _appendData(chunk);
    notifyListeners();
  }

  void commitStream() {
    if (!_streamingDraftMode) {
      return;
    }
    _streamingDraftMode = false;
    _syncStreamingState();
    notifyListeners();
  }

  void clear() {
    if (_source.isEmpty) {
      return;
    }
    _streamingDraftMode = false;
    _replaceData('');
    notifyListeners();
  }

  @override
  void dispose() {
    _documentVersionNotifier.dispose();
    super.dispose();
  }

  String serialize(MarkdownCopySerializer serializer) {
    return serializer.serialize(_document);
  }

  Future<void> copyPlainTextToClipboard() {
    return Clipboard.setData(ClipboardData(text: plainText));
  }

  void _appendData(String chunk) {
    final previousDocument = _document;
    final previousSourceLength = _source.length;
    final lastRange = previousDocument.blocks.isEmpty
        ? null
        : previousDocument.blocks.last.sourceRange;
    final previousTailLines = lastRange == null
        ? const <String>['']
        : _source.linesFromOffset(lastRange.start);
    final append = _source.append(chunk);
    _version += 1;
    final parseStopwatch = Stopwatch()..start();
    const parseMode = 'appendChunk';
    _document = _parser.parseAppendingChunk(
      _source.lines,
      previousDocument: previousDocument,
      appendedLines: append.lines,
      previousTailLines: previousTailLines,
      previousSourceLength: previousSourceLength,
      previousSourceEndsWithNewline: append.previousSourceEndsWithNewline,
      previousSourceEndsWithBlankLine: append.previousSourceEndsWithBlankLine,
      version: _version,
    );
    parseStopwatch.stop();
    if (mixinMarkdownDebugLogging) {
      debugPrint(
        '[mixin_markdown_widget] parse mode=$parseMode '
        'version=$_version chars=${_source.length} '
        'blocks=${_document.blocks.length} '
        'elapsed=${parseStopwatch.elapsedMicroseconds / 1000}ms',
      );
    }
    _syncStreamingState();
    _documentVersionNotifier.value = _version;
  }

  void _replaceData(String data, {MarkdownDocument? document}) {
    _source.set(data);
    _version += 1;
    final parseStopwatch = Stopwatch()..start();
    const parseMode = 'full';
    _document = document != null && document.version == _version
        ? document
        : _parser.parseLines(_source.lines, version: _version);
    parseStopwatch.stop();
    if (mixinMarkdownDebugLogging) {
      debugPrint(
        '[mixin_markdown_widget] parse mode=$parseMode '
        'version=$_version chars=${_source.length} '
        'blocks=${_document.blocks.length} '
        'elapsed=${parseStopwatch.elapsedMicroseconds / 1000}ms',
      );
    }
    _syncStreamingState();
    _documentVersionNotifier.value = _version;
  }

  void _syncStreamingState() {
    if (!_streamingDraftMode || _document.blocks.isEmpty) {
      _streamingState = StreamingMarkdownState.lazyBuffer(
        committedBlocks: List<BlockNode>.unmodifiable(_document.blocks),
        draftBlock: null,
        bufferProvider: _source.createTextProvider(),
        version: _version,
      );
      return;
    }
    _streamingState = StreamingMarkdownState.lazyBuffer(
      committedBlocks: _BlockPrefixView(
        _document.blocks,
        _document.blocks.length - 1,
      ),
      draftBlock: _document.blocks.last,
      bufferProvider: _source.createTextProvider(),
      version: _version,
    );
  }
}

class _MarkdownSourceBuffer {
  final List<String> _lines = <String>[''];
  final List<int> _lineStarts = <int>[0];
  int _length = 0;
  bool _pendingCarriageReturn = false;
  String? _cachedText;

  bool get isEmpty => _length == 0;
  int get length => _length;
  List<String> get lines => _lines;

  bool get endsWithNewline =>
      _length > 0 && _lines.length > 1 && _lines.last.isEmpty;

  bool get endsWithBlankLine =>
      _length > 1 &&
      _lines.length > 2 &&
      _lines[_lines.length - 1].isEmpty &&
      _lines[_lines.length - 2].isEmpty;

  String get text => _cachedText ??= _lines.join('\n');

  void set(String source) {
    _lines
      ..clear()
      ..add('');
    _lineStarts
      ..clear()
      ..add(0);
    _length = 0;
    _pendingCarriageReturn = false;
    _cachedText = null;
    append(source);
  }

  _MarkdownSourceAppend append(String chunk) {
    final previousEndsWithNewline = endsWithNewline;
    final previousEndsWithBlankLine = endsWithBlankLine;
    final normalizedChunk = _normalizeChunk(chunk);
    final appendedLines = normalizedChunk.split('\n');
    if (normalizedChunk.isNotEmpty) {
      _appendNormalized(normalizedChunk, appendedLines);
    }
    return _MarkdownSourceAppend(
      lines: appendedLines,
      previousSourceEndsWithNewline: previousEndsWithNewline,
      previousSourceEndsWithBlankLine: previousEndsWithBlankLine,
    );
  }

  List<String> linesFromOffset(int offset) {
    RangeError.checkValueInInterval(offset, 0, _length, 'offset');
    if (offset == 0) {
      return List<String>.unmodifiable(_lines);
    }
    if (offset == _length) {
      return const <String>[''];
    }

    final index = _lineIndexAtOffset(offset);
    final line = _lines[index];
    final lineStart = _lineStarts[index];
    return List<String>.unmodifiable(<String>[
      line.substring(offset - lineStart),
      ..._lines.skip(index + 1),
    ]);
  }

  String Function() createTextProvider() {
    final lines = List<String>.of(_lines, growable: false);
    String? text;
    return () => text ??= lines.join('\n');
  }

  String _normalizeChunk(String chunk) {
    if (chunk.isEmpty) {
      return '';
    }
    final buffer = StringBuffer();
    var index = 0;
    if (_pendingCarriageReturn) {
      if (chunk.codeUnitAt(0) == 0x0A) {
        index = 1;
      }
      _pendingCarriageReturn = false;
    }

    while (index < chunk.length) {
      final codeUnit = chunk.codeUnitAt(index);
      if (codeUnit == 0x0D) {
        buffer.write('\n');
        if (index + 1 < chunk.length && chunk.codeUnitAt(index + 1) == 0x0A) {
          index += 2;
          _pendingCarriageReturn = false;
        } else {
          index += 1;
          _pendingCarriageReturn = index == chunk.length;
        }
        continue;
      }
      buffer.writeCharCode(codeUnit);
      _pendingCarriageReturn = false;
      index += 1;
    }
    return buffer.toString();
  }

  void _appendNormalized(String normalizedChunk, List<String> appendedLines) {
    _cachedText = null;
    final previousLength = _length;
    _lines[_lines.length - 1] = '${_lines.last}${appendedLines.first}';
    if (appendedLines.length > 1) {
      var nextLineStart = previousLength + appendedLines.first.length + 1;
      for (var index = 1; index < appendedLines.length; index += 1) {
        _lineStarts.add(nextLineStart);
        nextLineStart += appendedLines[index].length + 1;
      }
      _lines.addAll(appendedLines.skip(1));
    }
    _length += normalizedChunk.length;
  }

  int _lineIndexAtOffset(int offset) {
    var low = 0;
    var high = _lineStarts.length - 1;
    while (low <= high) {
      final mid = low + ((high - low) >> 1);
      final lineStart = _lineStarts[mid];
      if (lineStart > offset) {
        high = mid - 1;
        continue;
      }
      if (mid + 1 < _lineStarts.length && _lineStarts[mid + 1] <= offset) {
        low = mid + 1;
        continue;
      }
      return mid;
    }
    return _lineStarts.length - 1;
  }
}

class _MarkdownSourceAppend {
  const _MarkdownSourceAppend({
    required this.lines,
    required this.previousSourceEndsWithNewline,
    required this.previousSourceEndsWithBlankLine,
  });

  final List<String> lines;
  final bool previousSourceEndsWithNewline;
  final bool previousSourceEndsWithBlankLine;
}

class _BlockPrefixView extends ListBase<BlockNode> {
  _BlockPrefixView(this._source, this.length);

  final List<BlockNode> _source;

  @override
  final int length;

  @override
  set length(int newLength) {
    throw UnsupportedError('Cannot modify block prefix view length.');
  }

  @override
  BlockNode operator [](int index) {
    RangeError.checkValidIndex(index, this, null, length);
    return _source[index];
  }

  @override
  void operator []=(int index, BlockNode value) {
    throw UnsupportedError('Cannot modify block prefix view contents.');
  }
}
