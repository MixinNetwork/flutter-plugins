import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../clipboard/copy_serializer.dart';
import '../clipboard/plain_text_serializer.dart';
import '../core/document.dart';
import '../parser/markdown_document_parser.dart';
import '../streaming/streaming_state.dart';

class MarkdownController extends ChangeNotifier {
  MarkdownController({
    String data = '',
    MarkdownDocumentParser? parser,
    MarkdownCopySerializer? plainTextSerializer,
  })  : _parser = parser ?? const MarkdownDocumentParser(),
        _plainTextSerializer =
            plainTextSerializer ?? const MarkdownPlainTextSerializer() {
    _replaceData(data, allowIncrementalAppend: false);
  }

  final MarkdownDocumentParser _parser;
  final MarkdownCopySerializer _plainTextSerializer;
  final ValueNotifier<int> _documentVersionNotifier = ValueNotifier<int>(0);

  MarkdownDocument _document = const MarkdownDocument.empty();
  StreamingMarkdownState _streamingState = const StreamingMarkdownState.empty();
  String _data = '';
  int _version = 0;
  bool _streamingDraftMode = false;

  MarkdownDocument get document => _document;
  Listenable get documentListenable => _documentVersionNotifier;
  StreamingMarkdownState get streamingState => _streamingState;
  String get data => _data;
  String get plainText => _plainTextSerializer.serialize(_document);
  int get version => _version;

  void setData(String data) {
    if (data == _data) {
      return;
    }
    _streamingDraftMode = false;
    _replaceData(data, allowIncrementalAppend: false);
    notifyListeners();
  }

  void replaceAll(String data) => setData(data);

  void appendChunk(String chunk) {
    if (chunk.isEmpty) {
      return;
    }
    _streamingDraftMode = true;
    _replaceData('$_data$chunk', allowIncrementalAppend: true);
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
    if (_data.isEmpty) {
      return;
    }
    _streamingDraftMode = false;
    _replaceData('', allowIncrementalAppend: false);
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

  void _replaceData(
    String data, {
    required bool allowIncrementalAppend,
  }) {
    final previousDocument = _document;
    final previousData = _data;
    _data = data;
    _version += 1;
    if (allowIncrementalAppend &&
        previousData.isNotEmpty &&
        _data.startsWith(previousData)) {
      _document = _parser.parseAppending(
        _data,
        previousDocument: previousDocument,
        version: _version,
      );
    } else {
      _document = _parser.parse(_data, version: _version);
    }
    _syncStreamingState();
    _documentVersionNotifier.value = _version;
  }

  void _syncStreamingState() {
    if (!_streamingDraftMode || _document.blocks.isEmpty) {
      _streamingState = StreamingMarkdownState(
        committedBlocks: List<BlockNode>.unmodifiable(_document.blocks),
        draftBlock: null,
        buffer: _data,
        version: _version,
      );
      return;
    }
    _streamingState = StreamingMarkdownState(
      committedBlocks: List<BlockNode>.unmodifiable(
        _document.blocks.take(_document.blocks.length - 1),
      ),
      draftBlock: _document.blocks.last,
      buffer: _data,
      version: _version,
    );
  }
}
