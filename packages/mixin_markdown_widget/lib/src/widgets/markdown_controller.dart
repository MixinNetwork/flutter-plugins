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
    _replaceData(data);
  }

  final MarkdownDocumentParser _parser;
  final MarkdownCopySerializer _plainTextSerializer;

  MarkdownDocument _document = const MarkdownDocument.empty();
  StreamingMarkdownState _streamingState = const StreamingMarkdownState.empty();
  String _data = '';
  int _version = 0;
  bool _streamingDraftMode = false;

  MarkdownDocument get document => _document;
  StreamingMarkdownState get streamingState => _streamingState;
  String get data => _data;
  String get plainText => _plainTextSerializer.serialize(_document);
  int get version => _version;

  void setData(String data) {
    if (data == _data) {
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
    _replaceData('$_data$chunk');
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
    _replaceData('');
    notifyListeners();
  }

  String serialize(MarkdownCopySerializer serializer) {
    return serializer.serialize(_document);
  }

  Future<void> copyPlainTextToClipboard() {
    return Clipboard.setData(ClipboardData(text: plainText));
  }

  void _replaceData(String data) {
    _data = data;
    _version += 1;
    _document = _parser.parse(_data, version: _version);
    _syncStreamingState();
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
