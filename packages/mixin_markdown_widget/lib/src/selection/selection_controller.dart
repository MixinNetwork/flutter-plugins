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
  TableCellSelection? _tableCellSelection;

  MarkdownDocument get document => _document;
  DocumentSelection? get selection => _selection;
  TableCellSelection? get tableCellSelection => _tableCellSelection;
  DocumentRange? get normalizedRange => _selection?.normalizedRange;
  TableCellRange? get normalizedTableCellRange =>
      _tableCellSelection?.normalizedRange;
  bool get hasTextSelection => _selection != null;
  bool get hasTableSelection => _tableCellSelection != null;
  bool get hasSelection => hasTextSelection || hasTableSelection;

  String get selectedPlainText {
    final tableCellSelection = _tableCellSelection;
    if (tableCellSelection != null) {
      return _serializer.serializeTableCellSelection(
        _document,
        tableCellSelection,
      );
    }
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

    final tableSelection = _tableCellSelection;
    if (tableSelection != null) {
      final clampedTableSelection =
          _serializer.clampTableCellSelection(_document, tableSelection);
      if (_tableCellSelection != clampedTableSelection) {
        _tableCellSelection = clampedTableSelection;
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
    if (_selection == nextSelection && _tableCellSelection == null) {
      return;
    }
    _selection = nextSelection;
    _tableCellSelection = null;
    notifyListeners();
  }

  void setTableCellSelection(TableCellSelection? selection) {
    final nextSelection = selection == null
        ? null
        : _serializer.clampTableCellSelection(_document, selection);
    if (_tableCellSelection == nextSelection && _selection == null) {
      return;
    }
    _tableCellSelection = nextSelection;
    _selection = null;
    notifyListeners();
  }

  void clear() {
    if (_selection == null && _tableCellSelection == null) {
      return;
    }
    _selection = null;
    _tableCellSelection = null;
    notifyListeners();
  }

  void selectAll([MarkdownDocument? document]) {
    if (document != null) {
      _document = document;
    }
    final nextSelection = _serializer.createFullDocumentSelection(_document);
    if (_selection == nextSelection && _tableCellSelection == null) {
      return;
    }
    _selection = nextSelection;
    _tableCellSelection = null;
    notifyListeners();
  }

  Future<void> copySelectionToClipboard() {
    if (!hasSelection) {
      return Future<void>.value();
    }
    final text = selectedPlainText;
    if (text.isEmpty) {
      return Future<void>.value();
    }
    return Clipboard.setData(ClipboardData(text: text));
  }
}
