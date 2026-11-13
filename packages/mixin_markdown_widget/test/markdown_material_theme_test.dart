import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mixin_markdown_widget/mixin_markdown_widget.dart';

void main() {
  testWidgets('resolves markdown extensions from the material_ui theme', (
    tester,
  ) async {
    late MarkdownThemeData markdownTheme;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            markdownTheme = MarkdownThemeData.fallback(context).copyWith(
              bodyStyle: const TextStyle(color: Colors.red, fontSize: 19),
            );
            return Theme(
              data: ThemeData(extensions: [markdownTheme]),
              child: Builder(
                builder: (context) {
                  expect(
                    Theme.of(context).extension<MarkdownThemeData>(),
                    same(markdownTheme),
                  );
                  expect(MarkdownTheme.of(context), same(markdownTheme));
                  return const Scaffold(
                    body: MarkdownWidget(data: 'Themed markdown'),
                  );
                },
              ),
            );
          },
        ),
      ),
    );

    expect(
      MarkdownTheme.of(tester.element(find.byType(MarkdownWidget))),
      same(markdownTheme),
    );
    expect(tester.takeException(), isNull);
  });
}
