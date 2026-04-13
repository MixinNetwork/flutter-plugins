import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import '../lib/main.dart';

void main() {
  testWidgets('demo app renders initial markdown content', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const DemoApp());

    expect(find.text('mixin_markdown_widget'), findsWidgets);
    expect(find.byKey(const Key('markdown-editor')), findsOneWidget);
    expect(find.byKey(const Key('markdown-preview')), findsOneWidget);
    expect(find.byIcon(Icons.palette_outlined), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('markdown-editor')),
      '# Custom Title\n\nUser defined content.',
    );
    await tester.pumpAndSettle();

    expect(find.text('Custom Title'), findsOneWidget);
    expect(find.text('User defined content.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('toggle-editor-visibility')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('markdown-editor')), findsNothing);
    expect(find.byKey(const Key('markdown-preview')), findsOneWidget);
    expect(
      find.textContaining('Preview-only mode. Current theme: Ocean.'),
      findsOneWidget,
    );
  });
}
