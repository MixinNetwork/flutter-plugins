import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:word_segmenter/word_segmenter.dart';
import 'package:word_segmenter_example/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('segments Chinese with the system dictionary', () {
    const text = '我们今天讨论一下，Hello world!';
    final segments = [
      for (final range in wordBoundaries(text)!) range.textInside(text),
    ];
    expect(segments.join(), text);
    expect(
      segments,
      containsAllInOrder(['我们', '今天', '讨论', '，', 'Hello', ' ', 'world']),
    );
  });

  testWidgets('example shows the segments', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    expect(find.text('我们'), findsOneWidget);
    expect(find.text('No word segmenter on this platform.'), findsNothing);
  });
}
