import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../core/document.dart';
import '../../widgets/markdown_theme.dart';
import '../../widgets/markdown_types.dart';
import '../pretext_text_block.dart';

class MarkdownInlineBuilder {
  MarkdownInlineBuilder({
    required this.theme,
    required this.recognizers,
    this.onTapLink,
  });

  final MarkdownThemeData theme;
  final List<TapGestureRecognizer> recognizers;
  final MarkdownTapLinkCallback? onTapLink;

  List<MarkdownPretextInlineRun> buildPretextRuns(
      TextStyle baseStyle, List<InlineNode> inlines,
      {bool alignInlineMathToBaseline = true}) {
    return <MarkdownPretextInlineRun>[
      for (final inline in inlines)
        ..._buildPretextRun(
          baseStyle,
          inline,
          alignInlineMathToBaseline: alignInlineMathToBaseline,
        ),
    ];
  }

  List<MarkdownPretextInlineRun> _buildPretextRun(
      TextStyle baseStyle, InlineNode inline,
      {required bool alignInlineMathToBaseline}) {
    switch (inline.kind) {
      case MarkdownInlineKind.text:
        return <MarkdownPretextInlineRun>[
          MarkdownPretextInlineRun(
            text: (inline as TextInline).text,
            style: baseStyle,
          ),
        ];
      case MarkdownInlineKind.emphasis:
        final emphasis = inline as EmphasisInline;
        final style = baseStyle.copyWith(fontStyle: FontStyle.italic);
        return buildPretextRuns(
          style,
          emphasis.children,
          alignInlineMathToBaseline: alignInlineMathToBaseline,
        );
      case MarkdownInlineKind.strong:
        final strong = inline as StrongInline;
        final style = baseStyle.copyWith(fontWeight: FontWeight.w700);
        return buildPretextRuns(
          style,
          strong.children,
          alignInlineMathToBaseline: alignInlineMathToBaseline,
        );
      case MarkdownInlineKind.strikethrough:
        final strike = inline as StrikethroughInline;
        final style =
            baseStyle.copyWith(decoration: TextDecoration.lineThrough);
        return buildPretextRuns(
          style,
          strike.children,
          alignInlineMathToBaseline: alignInlineMathToBaseline,
        );
      case MarkdownInlineKind.highlight:
        final highlight = inline as HighlightInline;
        return buildPretextRuns(
          highlightStyle(baseStyle),
          highlight.children,
          alignInlineMathToBaseline: alignInlineMathToBaseline,
        );
      case MarkdownInlineKind.subscript:
        final subscript = inline as SubscriptInline;
        return buildPretextRuns(
          subscriptStyle(baseStyle),
          subscript.children,
          alignInlineMathToBaseline: alignInlineMathToBaseline,
        );
      case MarkdownInlineKind.superscript:
        final superscript = inline as SuperscriptInline;
        return buildPretextRuns(
          superscriptStyle(baseStyle),
          superscript.children,
          alignInlineMathToBaseline: alignInlineMathToBaseline,
        );
      case MarkdownInlineKind.link:
        final link = inline as LinkInline;
        final label = flattenInlineText(link.children);
        final recognizer = onTapLink == null
            ? null
            : _registerLink(() {
                onTapLink!(link.destination, link.title, label);
              });
        final style = baseStyle.merge(theme.linkStyle);
        return buildPretextRuns(
          style,
          link.children,
          alignInlineMathToBaseline: alignInlineMathToBaseline,
        )
            .map(
              (run) => MarkdownPretextInlineRun(
                text: run.text,
                style: run.style,
                mouseCursor: onTapLink != null
                    ? SystemMouseCursors.click
                    : MouseCursor.defer,
                recognizer: recognizer,
                decoration: run.decoration,
                allowCharacterWrap: run.allowCharacterWrap,
                renderSpan: run.renderSpan,
                estimatedWidth: run.estimatedWidth,
                estimatedLineHeight: run.estimatedLineHeight,
              ),
            )
            .toList(growable: false);
      case MarkdownInlineKind.math:
        final math = inline as MathInline;
        return <MarkdownPretextInlineRun>[
          MarkdownPretextInlineRun(
            text: math.tex,
            style: baseStyle.merge(theme.inlineCodeStyle),
            renderSpan: _buildMathSpan(
              baseStyle,
              math,
              alignToBaseline: alignInlineMathToBaseline,
            ),
            estimatedWidth: _estimateMathWidth(baseStyle, math),
            estimatedLineHeight: _estimateMathLineHeight(baseStyle, math),
          ),
        ];
      case MarkdownInlineKind.inlineCode:
        final code = inline as InlineCode;
        return <MarkdownPretextInlineRun>[
          MarkdownPretextInlineRun(
            text: code.text,
            style: baseStyle.merge(theme.inlineCodeStyle),
            allowCharacterWrap: true,
            decoration: MarkdownPretextInlineDecoration(
              backgroundColor: theme.inlineCodeBackgroundColor,
              borderRadius: theme.inlineCodeBorderRadius,
              padding: theme.inlineCodePadding,
            ),
          ),
        ];
      case MarkdownInlineKind.softBreak:
      case MarkdownInlineKind.hardBreak:
        return <MarkdownPretextInlineRun>[
          MarkdownPretextInlineRun(
            text: '\n',
            style: baseStyle,
          ),
        ];
      case MarkdownInlineKind.image:
        final image = inline as InlineImage;
        final label = image.alt?.trim().isNotEmpty == true
            ? image.alt!.trim()
            : image.url;
        return <MarkdownPretextInlineRun>[
          MarkdownPretextInlineRun(
            text: label,
            style: baseStyle.merge(theme.linkStyle),
          ),
        ];
    }
  }

  List<InlineSpan> buildInlineSpans(
    TextStyle baseStyle,
    List<InlineNode> inlines,
  ) {
    return <InlineSpan>[
      for (final inline in inlines) ..._buildInlineSpan(baseStyle, inline),
    ];
  }

  List<InlineSpan> _buildInlineSpan(TextStyle baseStyle, InlineNode inline) {
    switch (inline.kind) {
      case MarkdownInlineKind.text:
        return <InlineSpan>[TextSpan(text: (inline as TextInline).text)];
      case MarkdownInlineKind.emphasis:
        final emphasis = inline as EmphasisInline;
        return <InlineSpan>[
          TextSpan(
            style: baseStyle.copyWith(fontStyle: FontStyle.italic),
            children: buildInlineSpans(
              baseStyle.copyWith(fontStyle: FontStyle.italic),
              emphasis.children,
            ),
          ),
        ];
      case MarkdownInlineKind.strong:
        final strong = inline as StrongInline;
        return <InlineSpan>[
          TextSpan(
            style: baseStyle.copyWith(fontWeight: FontWeight.w700),
            children: buildInlineSpans(
              baseStyle.copyWith(fontWeight: FontWeight.w700),
              strong.children,
            ),
          ),
        ];
      case MarkdownInlineKind.strikethrough:
        final strike = inline as StrikethroughInline;
        return <InlineSpan>[
          TextSpan(
            style: baseStyle.copyWith(decoration: TextDecoration.lineThrough),
            children: buildInlineSpans(
              baseStyle.copyWith(decoration: TextDecoration.lineThrough),
              strike.children,
            ),
          ),
        ];
      case MarkdownInlineKind.highlight:
        final highlight = inline as HighlightInline;
        final style = highlightStyle(baseStyle);
        return <InlineSpan>[
          TextSpan(
            style: style,
            children: buildInlineSpans(style, highlight.children),
          ),
        ];
      case MarkdownInlineKind.subscript:
        final subscript = inline as SubscriptInline;
        final style = subscriptStyle(baseStyle);
        return <InlineSpan>[
          TextSpan(
            style: style,
            children: buildInlineSpans(style, subscript.children),
          ),
        ];
      case MarkdownInlineKind.superscript:
        final superscript = inline as SuperscriptInline;
        final style = superscriptStyle(baseStyle);
        return <InlineSpan>[
          TextSpan(
            style: style,
            children: buildInlineSpans(style, superscript.children),
          ),
        ];
      case MarkdownInlineKind.link:
        final link = inline as LinkInline;
        final label = flattenInlineText(link.children);
        final recognizer = onTapLink == null
            ? null
            : _registerLink(() {
                onTapLink!(link.destination, link.title, label);
              });
        final style = baseStyle.merge(theme.linkStyle);
        return <InlineSpan>[
          TextSpan(
            style: style,
            mouseCursor: onTapLink != null
                ? SystemMouseCursors.click
                : MouseCursor.defer,
            recognizer: recognizer,
            children: buildInlineSpans(style, link.children),
          ),
        ];
      case MarkdownInlineKind.math:
        final math = inline as MathInline;
        return <InlineSpan>[
          _buildMathSpan(baseStyle, math, alignToBaseline: true),
        ];
      case MarkdownInlineKind.inlineCode:
        final code = inline as InlineCode;
        return <InlineSpan>[
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.inlineCodeBackgroundColor,
                borderRadius: theme.inlineCodeBorderRadius,
              ),
              child: Padding(
                padding: theme.inlineCodePadding,
                child: Text(
                  code.text,
                  style: baseStyle.merge(theme.inlineCodeStyle),
                ),
              ),
            ),
          ),
        ];
      case MarkdownInlineKind.softBreak:
      case MarkdownInlineKind.hardBreak:
        return const <InlineSpan>[TextSpan(text: '\n')];
      case MarkdownInlineKind.image:
        final image = inline as InlineImage;
        final label = image.alt?.trim().isNotEmpty == true
            ? image.alt!.trim()
            : image.url;
        return <InlineSpan>[
          TextSpan(
            text: label,
            style: baseStyle.merge(theme.linkStyle),
          ),
        ];
    }
  }

  TapGestureRecognizer _registerLink(VoidCallback onTap) {
    final recognizer = TapGestureRecognizer()..onTap = onTap;
    recognizers.add(recognizer);
    return recognizer;
  }

  TextStyle highlightStyle(TextStyle baseStyle) {
    final accent = theme.linkStyle.color ?? theme.dividerColor;
    return baseStyle.copyWith(
      backgroundColor: accent.withValues(alpha: 0.18),
    );
  }

  TextStyle subscriptStyle(TextStyle baseStyle) {
    final baseFontSize = baseStyle.fontSize ?? theme.bodyStyle.fontSize ?? 16;
    return baseStyle.copyWith(
      fontSize: baseFontSize * 0.82,
      fontFeatures: const <FontFeature>[FontFeature.subscripts()],
    );
  }

  TextStyle superscriptStyle(TextStyle baseStyle) {
    final baseFontSize = baseStyle.fontSize ?? theme.bodyStyle.fontSize ?? 16;
    return baseStyle.copyWith(
      fontSize: baseFontSize * 0.82,
      fontFeatures: const <FontFeature>[FontFeature.superscripts()],
    );
  }

  WidgetSpan _buildMathSpan(
    TextStyle baseStyle,
    MathInline math, {
    required bool alignToBaseline,
  }) {
    final child = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: math.displayStyle ? 0 : 2,
        vertical: math.displayStyle ? 6 : 0,
      ),
      child: Math.tex(
        math.tex,
        mathStyle: math.displayStyle ? MathStyle.display : MathStyle.text,
        textStyle: baseStyle,
        onErrorFallback: (error) => Text(
          math.tex,
          style: baseStyle.merge(theme.inlineCodeStyle),
        ),
      ),
    );
    final useBaselineAlignment = !math.displayStyle && alignToBaseline;
    return WidgetSpan(
      alignment: useBaselineAlignment
          ? PlaceholderAlignment.baseline
          : PlaceholderAlignment.middle,
      baseline: useBaselineAlignment ? TextBaseline.alphabetic : null,
      child: child,
    );
  }

  double _estimateMathWidth(TextStyle baseStyle, MathInline math) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: math.tex,
        style: baseStyle.merge(theme.inlineCodeStyle),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: double.infinity);
    return textPainter.width + (math.displayStyle ? 0 : 4);
  }

  double _estimateMathLineHeight(TextStyle baseStyle, MathInline math) {
    final textPainter = TextPainter(
      text: TextSpan(text: ' ', style: baseStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: double.infinity);
    final verticalPadding = math.displayStyle ? 12.0 : 4.0;
    final multiplier = math.displayStyle ? 1.9 : 1.35;
    return textPainter.preferredLineHeight * multiplier + verticalPadding;
  }

  static String flattenInlineText(List<InlineNode> inlines) {
    final buffer = StringBuffer();
    for (final inline in inlines) {
      switch (inline.kind) {
        case MarkdownInlineKind.text:
          buffer.write((inline as TextInline).text);
          break;
        case MarkdownInlineKind.emphasis:
          buffer.write(flattenInlineText((inline as EmphasisInline).children));
          break;
        case MarkdownInlineKind.strong:
          buffer.write(flattenInlineText((inline as StrongInline).children));
          break;
        case MarkdownInlineKind.strikethrough:
          buffer.write(
            flattenInlineText((inline as StrikethroughInline).children),
          );
          break;
        case MarkdownInlineKind.highlight:
          buffer.write(flattenInlineText((inline as HighlightInline).children));
          break;
        case MarkdownInlineKind.subscript:
          buffer.write(flattenInlineText((inline as SubscriptInline).children));
          break;
        case MarkdownInlineKind.superscript:
          buffer.write(
            flattenInlineText((inline as SuperscriptInline).children),
          );
          break;
        case MarkdownInlineKind.link:
          buffer.write(flattenInlineText((inline as LinkInline).children));
          break;
        case MarkdownInlineKind.math:
          buffer.write((inline as MathInline).tex);
          break;
        case MarkdownInlineKind.inlineCode:
          buffer.write((inline as InlineCode).text);
          break;
        case MarkdownInlineKind.softBreak:
        case MarkdownInlineKind.hardBreak:
          buffer.write('\n');
          break;
        case MarkdownInlineKind.image:
          final image = inline as InlineImage;
          buffer.write(image.alt ?? image.url);
          break;
      }
    }
    return buffer.toString();
  }

  static bool inlinesContainMath(List<InlineNode> inlines) {
    for (final inline in inlines) {
      switch (inline.kind) {
        case MarkdownInlineKind.math:
          return true;
        case MarkdownInlineKind.emphasis:
          if (inlinesContainMath((inline as EmphasisInline).children)) {
            return true;
          }
          break;
        case MarkdownInlineKind.strong:
          if (inlinesContainMath((inline as StrongInline).children)) {
            return true;
          }
          break;
        case MarkdownInlineKind.strikethrough:
          if (inlinesContainMath((inline as StrikethroughInline).children)) {
            return true;
          }
          break;
        case MarkdownInlineKind.highlight:
          if (inlinesContainMath((inline as HighlightInline).children)) {
            return true;
          }
          break;
        case MarkdownInlineKind.subscript:
          if (inlinesContainMath((inline as SubscriptInline).children)) {
            return true;
          }
          break;
        case MarkdownInlineKind.superscript:
          if (inlinesContainMath((inline as SuperscriptInline).children)) {
            return true;
          }
          break;
        case MarkdownInlineKind.link:
          if (inlinesContainMath((inline as LinkInline).children)) {
            return true;
          }
          break;
        case MarkdownInlineKind.text:
        case MarkdownInlineKind.inlineCode:
        case MarkdownInlineKind.softBreak:
        case MarkdownInlineKind.hardBreak:
        case MarkdownInlineKind.image:
          break;
      }
    }
    return false;
  }

  static bool isStandaloneDisplayMath(List<InlineNode> inlines) {
    if (inlines.length != 1) {
      return false;
    }
    final inline = inlines.single;
    return inline is MathInline && inline.displayStyle;
  }

  static TextAlign resolvedInlineTextAlign(List<InlineNode> inlines) {
    return isStandaloneDisplayMath(inlines)
        ? TextAlign.center
        : TextAlign.start;
  }
}
