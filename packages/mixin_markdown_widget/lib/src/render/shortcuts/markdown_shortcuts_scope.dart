import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/document.dart';
import '../../selection/selection_controller.dart';
import '../../widgets/markdown_types.dart';

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
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(
            LogicalKeyboardKey.keyC,
            control: true,
          ): CopySelectionPlainTextIntent(),
          SingleActivator(
            LogicalKeyboardKey.keyC,
            meta: true,
          ): CopySelectionPlainTextIntent(),
          SingleActivator(
            LogicalKeyboardKey.keyA,
            control: true,
          ): SelectAllMarkdownIntent(),
          SingleActivator(
            LogicalKeyboardKey.keyA,
            meta: true,
          ): SelectAllMarkdownIntent(),
          SingleActivator(
            LogicalKeyboardKey.keyC,
            control: true,
            shift: true,
          ): CopyFullDocumentPlainTextIntent(),
          SingleActivator(
            LogicalKeyboardKey.keyC,
            meta: true,
            shift: true,
          ): CopyFullDocumentPlainTextIntent(),
          SingleActivator(
            LogicalKeyboardKey.escape,
          ): ClearMarkdownSelectionIntent(),
        },
        child: child,
      ),
    );
  }
}

class MarkdownContextMenu {
  static void show(
    BuildContext context, {
    required ContextMenuController contextMenuController,
    required MarkdownSelectionController selectionController,
    required MarkdownDocument document,
    required Offset globalPosition,
    VoidCallback? onCopyPlainText,
    bool showCopyAllInContextMenu = true,
    MarkdownContextMenuBuilder? contextMenuBuilder,
  }) {
    final buttonItems = <ContextMenuButtonItem>[
      ContextMenuButtonItem(
        onPressed: () {
          contextMenuController.remove();
          selectionController.copySelectionToClipboard();
        },
        type: ContextMenuButtonType.copy,
      ),
      ContextMenuButtonItem(
        onPressed: () {
          contextMenuController.remove();
          selectionController.selectAll(document);
        },
        type: ContextMenuButtonType.selectAll,
      ),
      if (onCopyPlainText != null && showCopyAllInContextMenu)
        ContextMenuButtonItem(
          onPressed: () {
            contextMenuController.remove();
            onCopyPlainText.call();
          },
          label: 'Copy all',
        ),
      if (selectionController.hasSelection)
        ContextMenuButtonItem(
          onPressed: () {
            contextMenuController.remove();
            selectionController.clear();
          },
          label: 'Clear selection',
        ),
    ];

    final anchors = TextSelectionToolbarAnchors(
      primaryAnchor: globalPosition,
    );

    contextMenuController.show(
      context: context,
      contextMenuBuilder: (context) {
        if (contextMenuBuilder != null) {
          return contextMenuBuilder(
            context,
            selectionController,
            buttonItems,
            anchors,
          );
        }
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: anchors,
          buttonItems: buttonItems,
        );
      },
    );
  }
}
