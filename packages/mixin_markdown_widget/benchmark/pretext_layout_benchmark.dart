import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixin_markdown_widget/mixin_markdown_widget.dart';

/// Lays out new paragraphs with inline code, which take the pretext path, and
/// reports the time of each first build.
void main() {
  testWidgets('pretext layout benchmark', (tester) async {
    stdout.writeln('mixin_markdown_widget pretext layout benchmark');
    for (var round = 0; round < 6; round++) {
      final data = _buildPost(round);
      final stopwatch = Stopwatch()..start();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 380,
                child: MarkdownWidget(
                  data: data,
                  useColumn: true,
                  selectable: false,
                ),
              ),
            ),
          ),
        ),
      );
      stopwatch.stop();
      stdout.writeln(
        'round=$round chars=${data.length} '
        'build_ms=${(stopwatch.elapsedMicroseconds / 1000).toStringAsFixed(1)}',
      );
    }
  });
}

String _buildPost(int round) {
  const sentences = [
    '今天下午三点在会议室讨论新版本的发布计划，',
    '请先运行 `flutter analyze` 再提交，',
    '这次修改了 `ChatHistoryViewport` 的布局预算，',
    '滚动和切换会话都更流畅了。',
    'See `docs/release.md` for the **full** checklist, ',
    '并且确认 `pubspec.lock` 没有多余的变化。',
  ];
  final buffer = StringBuffer();
  for (var paragraph = 0; paragraph < 6; paragraph++) {
    for (var i = 0; i < 8; i++) {
      buffer.write(sentences[(round + paragraph + i * 5) % sentences.length]);
    }
    buffer.write(' $round-$paragraph\n\n');
  }
  return buffer.toString();
}
