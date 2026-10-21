import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixin_markdown_widget/mixin_markdown_widget.dart';

const _document = 'Hello brave world\n\nSecond paragraph here';

Offset _characterCenter(
  WidgetTester tester, {
  required String containing,
  required String character,
}) {
  final finder = find.byWidgetPredicate(
    (widget) =>
        widget is RichText && widget.text.toPlainText().contains(containing),
  );
  final richText = tester.widget<RichText>(finder.first);
  final renderBox = tester.renderObject<RenderBox>(finder.first);
  final text = richText.text.toPlainText();
  final offset = text.indexOf(character);
  final painter = TextPainter(
    text: richText.text,
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: renderBox.size.width);
  final box = painter
      .getBoxesForSelection(
        TextSelection(baseOffset: offset, extentOffset: offset + 1),
      )
      .first
      .toRect();
  painter.dispose();
  return renderBox.localToGlobal(box.center);
}

Future<void> _rightClick(
  WidgetTester tester,
  Offset position, {
  bool settle = true,
}) async {
  await tester.tapAt(
    position,
    buttons: kSecondaryMouseButton,
    kind: PointerDeviceKind.mouse,
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _doubleClick(WidgetTester tester, Offset position) async {
  await tester.tapAt(position, kind: PointerDeviceKind.mouse);
  await tester.pump();
  await tester.tapAt(position, kind: PointerDeviceKind.mouse);
  await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 1));
}

Finder get _menu => find.byType(AdaptiveTextSelectionToolbar);

/// Records what the app writes to the clipboard.
List<String> _mockClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return copied;
}

Future<MarkdownSelectionController> _pumpMarkdown(
  WidgetTester tester, {
  String data = _document,
  ScrollController? scrollController,
  MarkdownContextMenuBuilder? contextMenuBuilder =
      defaultMarkdownContextMenuBuilder,
}) async {
  final selectionController = MarkdownSelectionController();
  addTearDown(selectionController.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MarkdownWidget(
          data: data,
          selectionController: selectionController,
          scrollController: scrollController,
          contextMenuBuilder: contextMenuBuilder,
        ),
      ),
    ),
  );
  return selectionController;
}

void main() {
  group('right click selection', () {
    testWidgets(
      'selects the word under the pointer outside the selection',
      (tester) async {
        final selection = await _pumpMarkdown(tester);
        final brave =
            _characterCenter(tester, containing: 'Hello', character: 'v');
        // Left of `brave`: the menu opens to the right of the pointer.
        final hello =
            _characterCenter(tester, containing: 'Hello', character: 'H');

        await _rightClick(tester, brave);
        expect(selection.selectedPlainText, 'brave');
        expect(_menu, findsOneWidget);
        expect(find.text('Copy'), findsOneWidget);

        await _rightClick(tester, hello);
        expect(selection.selectedPlainText, 'Hello');
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

    testWidgets(
      'keeps the selection under the pointer and clears it elsewhere',
      (tester) async {
        final selection = await _pumpMarkdown(tester);
        final brave =
            _characterCenter(tester, containing: 'Hello', character: 'v');
        // Left of `brave`: the menu opens to the right of the pointer.
        final hello =
            _characterCenter(tester, containing: 'Hello', character: 'H');

        await _doubleClick(tester, brave);
        expect(selection.selectedPlainText, 'brave');

        await _rightClick(tester, brave);
        expect(selection.selectedPlainText, 'brave');
        expect(find.text('Copy'), findsOneWidget);

        await _rightClick(tester, hello);
        expect(selection.selectedPlainText, isEmpty);
        expect(_menu, findsOneWidget);
        expect(find.text('Copy'), findsNothing);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets(
      'applies inside MixinSelectionArea',
      (tester) async {
        final selection = MarkdownSelectionController();
        addTearDown(selection.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MixinSelectionArea(
                controller: selection,
                child: const MarkdownWidget(data: _document, useColumn: true),
              ),
            ),
          ),
        );

        await tester.pump();
        await _rightClick(
          tester,
          _characterCenter(tester, containing: 'Hello', character: 'v'),
          // MixinSelectionArea keeps scheduling frames, so it never settles.
          settle: false,
        );
        expect(selection.selectedPlainText, 'brave');
        expect(_menu, findsOneWidget);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  });

  group('menu', () {
    testWidgets(
      'buttons run their action and close the menu',
      (tester) async {
        final selection = await _pumpMarkdown(tester);

        await _rightClick(
          tester,
          _characterCenter(tester, containing: 'Hello', character: 'v'),
        );
        await tester.tap(find.text('Select all'));
        await tester.pumpAndSettle();

        expect(selection.selectedPlainText, contains('Second paragraph'));
        expect(_menu, findsNothing);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets(
      'Escape closes the menu and keeps the selection',
      (tester) async {
        final selection = await _pumpMarkdown(tester);
        final brave =
            _characterCenter(tester, containing: 'Hello', character: 'v');
        await _doubleClick(tester, brave);
        await _rightClick(tester, brave);
        expect(_menu, findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        expect(_menu, findsNothing);
        expect(selection.selectedPlainText, 'brave');
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets(
      'scrolling closes the menu',
      (tester) async {
        final scrollController = ScrollController();
        addTearDown(scrollController.dispose);
        await _pumpMarkdown(
          tester,
          data: [
            _document,
            for (var index = 0; index < 60; index++) 'Line $index',
          ].join('\n\n'),
          scrollController: scrollController,
        );

        await _rightClick(
          tester,
          _characterCenter(tester, containing: 'Hello', character: 'v'),
        );
        expect(_menu, findsOneWidget);

        scrollController.jumpTo(120);
        await tester.pumpAndSettle();

        expect(_menu, findsNothing);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets(
      'Copy copies the selection',
      (tester) async {
        final copied = _mockClipboard(tester);
        await _pumpMarkdown(tester);
        final brave =
            _characterCenter(tester, containing: 'Hello', character: 'v');
        await _doubleClick(tester, brave);
        await _rightClick(tester, brave);

        await tester.tap(find.text('Copy'));
        await tester.pumpAndSettle();

        expect(copied, ['brave']);
        expect(_menu, findsNothing);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets(
      'a null builder shows no menu and keeps the selection',
      (tester) async {
        final selection = await _pumpMarkdown(tester, contextMenuBuilder: null);
        final brave =
            _characterCenter(tester, containing: 'Hello', character: 'v');
        await _doubleClick(tester, brave);

        await _rightClick(
          tester,
          _characterCenter(tester, containing: 'Second', character: 'S'),
        );

        expect(_menu, findsNothing);
        expect(selection.selectedPlainText, 'brave');
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  });

  group('links', () {
    for (final (name, data, containing, character, destination) in [
      (
        'a plain link',
        'Read [the docs](https://example.com/docs) first',
        'Read',
        'docs',
        'https://example.com/docs',
      ),
      (
        'an emphasized link',
        'Read **[bold docs](https://example.com/bold)** first',
        'Read',
        'bold',
        'https://example.com/bold',
      ),
      (
        'a link in a table cell',
        '| Name | Link |\n| --- | --- |\n| A | [cell docs](https://example.com/cell) |',
        'cell docs',
        'c',
        'https://example.com/cell',
      ),
    ]) {
      testWidgets(
        'Copy link copies $name',
        (tester) async {
          final copied = _mockClipboard(tester);
          await _pumpMarkdown(tester, data: data);

          await _rightClick(
            tester,
            _characterCenter(
              tester,
              containing: containing,
              character: character,
            ),
          );
          await tester.tap(find.text('Copy link'));
          await tester.pumpAndSettle();

          expect(copied, [destination]);
          expect(_menu, findsNothing);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.windows),
      );
    }

    testWidgets(
      'plain text has no Copy link',
      (tester) async {
        await _pumpMarkdown(
          tester,
          data: 'Read [the docs](https://example.com/docs) first',
        );

        await _rightClick(
          tester,
          _characterCenter(tester, containing: 'Read', character: 'R'),
        );

        expect(_menu, findsOneWidget);
        expect(find.text('Copy link'), findsNothing);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  });

  testWidgets(
    'custom builders get the details and can hide the menu',
    (tester) async {
      MarkdownContextMenuDetails? received;
      final selection = await _pumpMarkdown(
        tester,
        data: 'Read [the docs](https://example.com/docs) first',
        contextMenuBuilder: (context, details) {
          received = details;
          return AdaptiveTextSelectionToolbar.buttonItems(
            anchors: details.anchors,
            buttonItems: [
              ...details.buttonItems,
              ContextMenuButtonItem(label: 'Search', onPressed: details.hide),
            ],
          );
        },
      );
      final target =
          _characterCenter(tester, containing: 'Read', character: 'docs');

      await _rightClick(tester, target);

      expect(received!.linkDestination, 'https://example.com/docs');
      expect(received!.anchors.primaryAnchor, target);
      expect(received!.selectionController, same(selection));
      expect(
        received!.buttonItems.map((item) => item.type),
        contains(ContextMenuButtonType.selectAll),
      );

      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      expect(_menu, findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
