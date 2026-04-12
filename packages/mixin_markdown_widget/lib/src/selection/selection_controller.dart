import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../clipboard/plain_text_serializer.dart';
import '../core/document.dart';

class MarkdownSelectionController extends ChangeNotifier {
  MarkdownSelectionController({
    MarkdownPlainTextSerializer? serializer,
  }) : _serializer = serializer ?? const MarkdownPlainTextSerializer();

  final MarkdownPlainTextSerializer _serializer;

  MarkdownDocument _document = const MarkdownDocument.empty();
  DocumentSelection? _selection;

  MarkdownDocument get document => _document;
  DocumentSelection? get selection => _selection;
  DocumentRange? get normalizedRange => _selection?.normalizedRange;
  bool get hasTextSelection => _selection != null;
  bool get hasSelection => hasTextSelection;

  String get selectedPlainText {
    final selection = _selection;
    if (selection == null) {
      return '';
    }
    return _serializer.serializeSelection(_document, selection);
  }

  void attachDocument(MarkdownDocument document) {
    _document = document;
    var changed = false;

    final selection = _selection;
    if (selection != null) {
      final clampedSelection = _serializer.clampSelection(_document, selection);
      if (_selection != clampedSelection) {
        _selection = clampedSelection;
        changed = true;
      }
    }

    if (changed) {
      notifyListeners();
    }
  }

  void setSelection(DocumentSelection? selection) {
    final nextSelection = selection == null
        ? null
        : _serializer.clampSelection(_document, selection);
    if (_selection == nextSelection) {
      return;
    }
    _selection = nextSelection;
    notifyListeners();
  }

  void clear() {
    if (_selection == null) {
      return;
    }
    _selection = null;
    notifyListeners();
  }

  void selectAll([MarkdownDocument? document]) {
    if (document != null) {
      _document = document;
    }
    final nextSelection = _serializer.createFullDocumentSelection(_document);
    if (_selection == nextSelection) {
      return;
    }
    _selection = nextSelection;
    notifyListeners();
  }

  Future<void> copySelectionToClipboard() {
    if (!hasSelection) {
      return Future<void>.value();
    }
    return Clipboard.setData(ClipboardData(text: selectedPlainText));
  }
}
