import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/document.dart';
import '../../selection/selection_controller.dart';

class CopyFullDocumentPlainTextIntent extends Intent {
  const CopyFullDocumentPlainTextIntent();
}

class CopySelectionPlainTextIntent extends Intent {
  const CopySelectionPlainTextIntent();
}

class SelectAllMarkdownIntent extends Intent {
  const SelectAllMarkdownIntent();
}

class ClearMarkdownSelectionIntent extends Intent {
  const ClearMarkdownSelectionIntent();
}

class MarkdownShortcutsScope extends StatelessWidget {
  const MarkdownShortcutsScope({
    super.key,
    required this.child,
    required this.selectionController,
    required this.document,
    this.onCopyPlainText,
  });

  final Widget child;
  final MarkdownSelectionController selectionController;
  final MarkdownDocument document;
  final VoidCallback? onCopyPlainText;

  @override
  Widget build(BuildContext context) {
    final shortcuts = <ShortcutActivator, Intent>{
      const SingleActivator(
        LogicalKeyboardKey.keyC,
        control: true,
      ): const CopySelectionPlainTextIntent(),
      const SingleActivator(
        LogicalKeyboardKey.keyC,
        meta: true,
      ): const CopySelectionPlainTextIntent(),
      const SingleActivator(
        LogicalKeyboardKey.keyA,
        control: true,
      ): const SelectAllMarkdownIntent(),
      const SingleActivator(
        LogicalKeyboardKey.keyA,
        meta: true,
      ): const SelectAllMarkdownIntent(),
      const SingleActivator(
        LogicalKeyboardKey.keyC,
        control: true,
        shift: true,
      ): const CopyFullDocumentPlainTextIntent(),
      const SingleActivator(
        LogicalKeyboardKey.keyC,
        meta: true,
        shift: true,
      ): const CopyFullDocumentPlainTextIntent(),
      if (selectionController.hasSelection)
        const SingleActivator(
          LogicalKeyboardKey.escape,
        ): const ClearMarkdownSelectionIntent(),
    };

    return Actions(
      actions: <Type, Action<Intent>>{
        CopySelectionPlainTextIntent:
            CallbackAction<CopySelectionPlainTextIntent>(
          onInvoke: (intent) {
            if (selectionController.hasSelection) {
              selectionController.copySelectionToClipboard();
            }
            return null;
          },
        ),
        SelectAllMarkdownIntent: CallbackAction<SelectAllMarkdownIntent>(
          onInvoke: (intent) {
            selectionController.selectAll(document);
            return null;
          },
        ),
        ClearMarkdownSelectionIntent:
            CallbackAction<ClearMarkdownSelectionIntent>(
          onInvoke: (intent) {
            selectionController.clear();
            return null;
          },
        ),
        CopyFullDocumentPlainTextIntent:
            CallbackAction<CopyFullDocumentPlainTextIntent>(
          onInvoke: (intent) {
            onCopyPlainText?.call();
            return null;
          },
        ),
      },
      child: Shortcuts(
        shortcuts: shortcuts,
        child: child,
      ),
    );
  }
}
