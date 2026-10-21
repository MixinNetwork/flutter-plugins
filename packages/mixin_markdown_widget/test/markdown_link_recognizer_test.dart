import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixin_markdown_widget/mixin_markdown_widget.dart';
import 'package:mixin_markdown_widget/src/render/pretext_text_block.dart';
import 'package:mixin_markdown_widget/src/render/selectable_block.dart';

const _listData = '- Visit [Example](https://example.com)\n\nTail';

GestureRecognizer? _linkRecognizer(WidgetTester tester) {
  for (final block in tester.widgetList<MarkdownPretextTextBlock>(
    find.byType(MarkdownPretextTextBlock),
  )) {
    for (final run in block.runs ?? const <MarkdownPretextInlineRun>[]) {
      if (run.text.contains('Example') && run.recognizer != null) {
        return run.recognizer;
      }
    }
  }
  return null;
}

Future<void> _tapLink(WidgetTester tester) async {
  final richTextFinder = find.byWidgetPredicate(
    (widget) =>
        widget is RichText &&
        widget.text.toPlainText().contains('Visit Example'),
  );
  final richText = tester.widget<RichText>(richTextFinder);
  final renderBox = tester.renderObject<RenderBox>(richTextFinder);
  final text = richText.text.toPlainText();
  final start = text.indexOf('Example');
  final painter = TextPainter(
    text: richText.text,
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: renderBox.size.width);
  final boxes = painter.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: start + 'Example'.length),
  );
  painter.dispose();
  await tester.tapAt(renderBox.localToGlobal(boxes.first.toRect().center));
  await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 1));
}

SelectableMarkdownBlock _firstBlockRow(WidgetTester tester) {
  return tester.widget<SelectableMarkdownBlock>(
    find.byType(SelectableMarkdownBlock).first,
  );
}

void main() {
  late Set<Object> disposed;
  void recordDisposed(ObjectEvent event) {
    if (event is ObjectDisposed) {
      disposed.add(event.object);
    }
  }

  setUp(() {
    disposed = Set<Object>.identity();
    FlutterMemoryAllocations.instance.addListener(recordDisposed);
  });

  tearDown(() {
    FlutterMemoryAllocations.instance.removeListener(recordDisposed);
  });

  testWidgets('a cached list row keeps a live link recognizer', (tester) async {
    final controller = MarkdownController(data: _listData);
    addTearDown(controller.dispose);
    final taps = <String>[];
    void onTapLink(String destination, String? title, String label) {
      taps.add(destination);
    }

    late StateSetter setState;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setter) {
              setState = setter;
              return MarkdownWidget(
                controller: controller,
                onTapLink: onTapLink,
              );
            },
          ),
        ),
      ),
    );
    final recognizer = _linkRecognizer(tester);
    expect(recognizer, isNotNull);

    // Rebuilds and an append that leaves the list alone reuse its row.
    final row = _firstBlockRow(tester);
    setState(() {});
    await tester.pump();
    controller.appendChunk(' paragraph');
    await tester.pump();
    expect(identical(_firstBlockRow(tester), row), isTrue);
    expect(identical(_linkRecognizer(tester), recognizer), isTrue);
    expect(disposed.contains(recognizer), isFalse);

    await _tapLink(tester);
    expect(taps, <String>['https://example.com']);

    // The recognizer goes with its link.
    controller.setData('No links here');
    await tester.pump();
    expect(disposed.contains(recognizer), isTrue);
  });

  testWidgets('a new onTapLink closure keeps cached rows and is called',
      (tester) async {
    final taps = <String>[];
    var generation = 0;
    late StateSetter setState;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setter) {
              setState = setter;
              final current = generation;
              return MarkdownWidget(
                data: _listData,
                onTapLink: (destination, title, label) {
                  taps.add('$current:$destination');
                },
              );
            },
          ),
        ),
      ),
    );
    final row = _firstBlockRow(tester);
    final recognizer = _linkRecognizer(tester);

    for (var index = 0; index < 3; index += 1) {
      setState(() => generation += 1);
      await tester.pump();
    }

    expect(identical(_firstBlockRow(tester), row), isTrue);
    expect(identical(_linkRecognizer(tester), recognizer), isTrue);
    expect(disposed.contains(recognizer), isFalse);
    await _tapLink(tester);
    expect(taps, <String>['3:https://example.com']);
  });

  testWidgets('removing onTapLink rebuilds rows without link recognizers',
      (tester) async {
    MarkdownTapLinkCallback? onTapLink = (destination, title, label) {};
    late StateSetter setState;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setter) {
              setState = setter;
              return MarkdownWidget(data: _listData, onTapLink: onTapLink);
            },
          ),
        ),
      ),
    );
    expect(_linkRecognizer(tester), isNotNull);

    setState(() => onTapLink = null);
    await tester.pump();
    expect(_linkRecognizer(tester), isNull);
  });
}
