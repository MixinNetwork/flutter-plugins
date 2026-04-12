import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class MarkdownTheme extends InheritedTheme {
  const MarkdownTheme({
    super.key,
    required this.data,
    required super.child,
  });

  final MarkdownThemeData data;

  static MarkdownThemeData of(BuildContext context) {
    final inheritedTheme =
        context.dependOnInheritedWidgetOfExactType<MarkdownTheme>();
    if (inheritedTheme != null) {
      return inheritedTheme.data;
    }
    final extension = Theme.of(context).extension<MarkdownThemeData>();
    if (extension != null) {
      return extension;
    }
    return MarkdownThemeData.fallback(context);
  }

  @override
  bool updateShouldNotify(MarkdownTheme oldWidget) => data != oldWidget.data;

  @override
  Widget wrap(BuildContext context, Widget child) {
    return MarkdownTheme(data: data, child: child);
  }
}

@immutable
class MarkdownThemeData extends ThemeExtension<MarkdownThemeData>
    with DiagnosticableTreeMixin {
  const MarkdownThemeData({
    required this.padding,
    required this.blockSpacing,
    required this.listItemSpacing,
    required this.maxContentWidth,
    required this.quotePadding,
    required this.inlineCodePadding,
    required this.codeBlockPadding,
    required this.tableCellPadding,
    required this.inlineCodeBorderRadius,
    required this.codeBlockBorderRadius,
    required this.imageBorderRadius,
    required this.quoteBorderRadius,
    required this.tableBorderRadius,
    required this.imageCaptionSpacing,
    required this.codeBlockToolbarPadding,
    required this.bodyStyle,
    required this.quoteStyle,
    required this.linkStyle,
    required this.inlineCodeStyle,
    required this.codeBlockStyle,
    required this.tableHeaderStyle,
    required this.heading1Style,
    required this.heading2Style,
    required this.heading3Style,
    required this.heading4Style,
    required this.heading5Style,
    required this.heading6Style,
    required this.quoteBackgroundColor,
    required this.quoteBorderColor,
    required this.inlineCodeBackgroundColor,
    required this.codeBlockBackgroundColor,
    required this.dividerColor,
    required this.tableBorderColor,
    required this.tableHeaderBackgroundColor,
    required this.tableRowBackgroundColor,
    required this.selectionColor,
    required this.quoteBorderWidth,
  });

  factory MarkdownThemeData.fallback(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;
    final borderColor =
        Color.lerp(colorScheme.outline, colorScheme.onSurface, 0.24) ??
            colorScheme.outline;
    final bodyStyle = (textTheme.bodyMedium ?? const TextStyle()).copyWith(
      fontSize: 16,
    );
    final mono = bodyStyle.copyWith(
      fontFamily: 'Mono',
      fontFamilyFallback: const <String>[
        'SF Mono',
        'Roboto Mono',
        'Menlo',
        'Monaco',
        'Consolas',
        'Liberation Mono',
        'Courier New',
        'monospace',
      ],
      fontSize: 15,
    );
    return MarkdownThemeData(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      blockSpacing: 16,
      listItemSpacing: 4,
      maxContentWidth: 920,
      quotePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      inlineCodePadding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      codeBlockPadding: const EdgeInsets.all(16),
      tableCellPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      inlineCodeBorderRadius: BorderRadius.circular(6),
      codeBlockBorderRadius: BorderRadius.circular(16),
      imageBorderRadius: BorderRadius.circular(6),
      quoteBorderRadius: BorderRadius.circular(4),
      tableBorderRadius: BorderRadius.circular(6),
      imageCaptionSpacing: 8,
      codeBlockToolbarPadding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
      bodyStyle: bodyStyle,
      quoteStyle: bodyStyle.copyWith(
        color: colorScheme.onSurface.withOpacity(0.82),
        fontStyle: FontStyle.italic,
      ),
      linkStyle: bodyStyle.copyWith(
        color: colorScheme.primary,
        decoration: TextDecoration.underline,
        decorationColor: colorScheme.primary,
      ),
      inlineCodeStyle: mono,
      codeBlockStyle: mono.copyWith(
        color: colorScheme.onSurface,
      ),
      tableHeaderStyle: bodyStyle.copyWith(fontWeight: FontWeight.w700),
      heading1Style:
          textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700) ??
              bodyStyle.copyWith(fontSize: 34, fontWeight: FontWeight.w700),
      heading2Style:
          textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700) ??
              bodyStyle.copyWith(fontSize: 28, fontWeight: FontWeight.w700),
      heading3Style:
          textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700) ??
              bodyStyle.copyWith(fontSize: 24, fontWeight: FontWeight.w700),
      heading4Style:
          textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700) ??
              bodyStyle.copyWith(fontSize: 21, fontWeight: FontWeight.w700),
      heading5Style:
          textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700) ??
              bodyStyle.copyWith(fontSize: 18, fontWeight: FontWeight.w700),
      heading6Style:
          textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700) ??
              bodyStyle.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
      quoteBackgroundColor: colorScheme.surface.withOpacity(0.7),
      quoteBorderColor: colorScheme.primary.withOpacity(0.4),
      inlineCodeBackgroundColor:
          Color.lerp(colorScheme.surface, colorScheme.onSurface, 0.06) ??
              colorScheme.surface,
      codeBlockBackgroundColor: colorScheme.surface.withOpacity(0.92),
      dividerColor: borderColor,
      tableBorderColor: borderColor,
      tableHeaderBackgroundColor: colorScheme.primary.withOpacity(0.08),
      tableRowBackgroundColor: colorScheme.surface,
      selectionColor: colorScheme.primary.withOpacity(0.24),
      quoteBorderWidth: 4,
    );
  }

  factory MarkdownThemeData.tight(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;
    final borderColor =
        Color.lerp(colorScheme.outline, colorScheme.onSurface, 0.24) ??
            colorScheme.outline;
    final bodyStyle =
        (textTheme.bodyMedium ?? const TextStyle()).copyWith(fontSize: 14);
    final mono = bodyStyle.copyWith(
      fontFamily: 'Mono',
      fontFamilyFallback: const <String>[
        'SF Mono',
        'Roboto Mono',
        'Menlo',
        'Monaco',
        'Consolas',
        'Liberation Mono',
        'Courier New',
        'monospace',
      ],
      fontSize: 13,
    );
    return MarkdownThemeData(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      blockSpacing: 10,
      listItemSpacing: 2,
      maxContentWidth: 920,
      quotePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      inlineCodePadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      codeBlockPadding: const EdgeInsets.all(12),
      tableCellPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      inlineCodeBorderRadius: BorderRadius.circular(4),
      codeBlockBorderRadius: BorderRadius.circular(8),
      imageBorderRadius: BorderRadius.circular(6),
      quoteBorderRadius: BorderRadius.circular(4),
      tableBorderRadius: BorderRadius.circular(4),
      imageCaptionSpacing: 4,
      codeBlockToolbarPadding: const EdgeInsets.fromLTRB(12, 6, 6, 0),
      bodyStyle: bodyStyle,
      quoteStyle: bodyStyle.copyWith(
        color: colorScheme.onSurface.withOpacity(0.82),
        fontStyle: FontStyle.italic,
      ),
      linkStyle: bodyStyle.copyWith(
        color: colorScheme.primary,
        decoration: TextDecoration.underline,
        decorationColor: colorScheme.primary,
      ),
      inlineCodeStyle: mono.copyWith(),
      codeBlockStyle: mono.copyWith(
        color: colorScheme.onSurface,
      ),
      tableHeaderStyle: bodyStyle.copyWith(fontWeight: FontWeight.w700),
      heading1Style:
          textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700) ??
              bodyStyle.copyWith(fontSize: 28, fontWeight: FontWeight.w700),
      heading2Style:
          textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700) ??
              bodyStyle.copyWith(fontSize: 22, fontWeight: FontWeight.w700),
      heading3Style:
          textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700) ??
              bodyStyle.copyWith(fontSize: 18, fontWeight: FontWeight.w700),
      heading4Style:
          textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700) ??
              bodyStyle.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
      heading5Style:
          textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700) ??
              bodyStyle.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
      heading6Style:
          textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700) ??
              bodyStyle.copyWith(fontSize: 13, fontWeight: FontWeight.w700),
      quoteBackgroundColor: colorScheme.surface.withOpacity(0.7),
      quoteBorderColor: colorScheme.primary.withOpacity(0.4),
      inlineCodeBackgroundColor:
          Color.lerp(colorScheme.surface, colorScheme.onSurface, 0.06) ??
              colorScheme.surface,
      codeBlockBackgroundColor: colorScheme.surface.withOpacity(0.92),
      dividerColor: borderColor,
      tableBorderColor: borderColor,
      tableHeaderBackgroundColor: colorScheme.primary.withOpacity(0.08),
      tableRowBackgroundColor: colorScheme.surface,
      selectionColor: colorScheme.primary.withOpacity(0.24),
      quoteBorderWidth: 4,
    );
  }

  final EdgeInsetsGeometry padding;
  final double blockSpacing;
  final double listItemSpacing;
  final double maxContentWidth;
  final EdgeInsetsGeometry quotePadding;
  final EdgeInsets inlineCodePadding;
  final EdgeInsetsGeometry codeBlockPadding;
  final EdgeInsetsGeometry tableCellPadding;
  final BorderRadius inlineCodeBorderRadius;
  final BorderRadius codeBlockBorderRadius;
  final BorderRadius imageBorderRadius;
  final BorderRadius quoteBorderRadius;
  final BorderRadius tableBorderRadius;
  final double imageCaptionSpacing;
  final EdgeInsetsGeometry codeBlockToolbarPadding;
  final TextStyle bodyStyle;
  final TextStyle quoteStyle;
  final TextStyle linkStyle;
  final TextStyle inlineCodeStyle;
  final TextStyle codeBlockStyle;
  final TextStyle tableHeaderStyle;
  final TextStyle heading1Style;
  final TextStyle heading2Style;
  final TextStyle heading3Style;
  final TextStyle heading4Style;
  final TextStyle heading5Style;
  final TextStyle heading6Style;
  final Color quoteBackgroundColor;
  final Color quoteBorderColor;
  final Color inlineCodeBackgroundColor;
  final Color codeBlockBackgroundColor;
  final Color dividerColor;
  final Color tableBorderColor;
  final Color tableHeaderBackgroundColor;
  final Color tableRowBackgroundColor;
  final Color selectionColor;
  final double quoteBorderWidth;

  TextStyle headingStyleForLevel(int level) {
    switch (level) {
      case 1:
        return heading1Style;
      case 2:
        return heading2Style;
      case 3:
        return heading3Style;
      case 4:
        return heading4Style;
      case 5:
        return heading5Style;
      case 6:
      default:
        return heading6Style;
    }
  }

  @override
  MarkdownThemeData copyWith({
    EdgeInsetsGeometry? padding,
    double? blockSpacing,
    double? listItemSpacing,
    double? maxContentWidth,
    EdgeInsetsGeometry? quotePadding,
    EdgeInsets? inlineCodePadding,
    EdgeInsetsGeometry? codeBlockPadding,
    EdgeInsetsGeometry? tableCellPadding,
    BorderRadius? inlineCodeBorderRadius,
    BorderRadius? codeBlockBorderRadius,
    BorderRadius? imageBorderRadius,
    BorderRadius? quoteBorderRadius,
    BorderRadius? tableBorderRadius,
    double? imageCaptionSpacing,
    EdgeInsetsGeometry? codeBlockToolbarPadding,
    TextStyle? bodyStyle,
    TextStyle? quoteStyle,
    TextStyle? linkStyle,
    TextStyle? inlineCodeStyle,
    TextStyle? codeBlockStyle,
    TextStyle? tableHeaderStyle,
    TextStyle? heading1Style,
    TextStyle? heading2Style,
    TextStyle? heading3Style,
    TextStyle? heading4Style,
    TextStyle? heading5Style,
    TextStyle? heading6Style,
    Color? quoteBackgroundColor,
    Color? quoteBorderColor,
    Color? inlineCodeBackgroundColor,
    Color? codeBlockBackgroundColor,
    Color? dividerColor,
    Color? tableBorderColor,
    Color? tableHeaderBackgroundColor,
    Color? tableRowBackgroundColor,
    Color? selectionColor,
    double? quoteBorderWidth,
  }) {
    return MarkdownThemeData(
      padding: padding ?? this.padding,
      blockSpacing: blockSpacing ?? this.blockSpacing,
      listItemSpacing: listItemSpacing ?? this.listItemSpacing,
      maxContentWidth: maxContentWidth ?? this.maxContentWidth,
      quotePadding: quotePadding ?? this.quotePadding,
      inlineCodePadding: inlineCodePadding ?? this.inlineCodePadding,
      codeBlockPadding: codeBlockPadding ?? this.codeBlockPadding,
      tableCellPadding: tableCellPadding ?? this.tableCellPadding,
      inlineCodeBorderRadius:
          inlineCodeBorderRadius ?? this.inlineCodeBorderRadius,
      codeBlockBorderRadius:
          codeBlockBorderRadius ?? this.codeBlockBorderRadius,
      imageBorderRadius: imageBorderRadius ?? this.imageBorderRadius,
      quoteBorderRadius: quoteBorderRadius ?? this.quoteBorderRadius,
      tableBorderRadius: tableBorderRadius ?? this.tableBorderRadius,
      imageCaptionSpacing: imageCaptionSpacing ?? this.imageCaptionSpacing,
      codeBlockToolbarPadding:
          codeBlockToolbarPadding ?? this.codeBlockToolbarPadding,
      bodyStyle: bodyStyle ?? this.bodyStyle,
      quoteStyle: quoteStyle ?? this.quoteStyle,
      linkStyle: linkStyle ?? this.linkStyle,
      inlineCodeStyle: inlineCodeStyle ?? this.inlineCodeStyle,
      codeBlockStyle: codeBlockStyle ?? this.codeBlockStyle,
      tableHeaderStyle: tableHeaderStyle ?? this.tableHeaderStyle,
      heading1Style: heading1Style ?? this.heading1Style,
      heading2Style: heading2Style ?? this.heading2Style,
      heading3Style: heading3Style ?? this.heading3Style,
      heading4Style: heading4Style ?? this.heading4Style,
      heading5Style: heading5Style ?? this.heading5Style,
      heading6Style: heading6Style ?? this.heading6Style,
      quoteBackgroundColor: quoteBackgroundColor ?? this.quoteBackgroundColor,
      quoteBorderColor: quoteBorderColor ?? this.quoteBorderColor,
      inlineCodeBackgroundColor:
          inlineCodeBackgroundColor ?? this.inlineCodeBackgroundColor,
      codeBlockBackgroundColor:
          codeBlockBackgroundColor ?? this.codeBlockBackgroundColor,
      dividerColor: dividerColor ?? this.dividerColor,
      tableBorderColor: tableBorderColor ?? this.tableBorderColor,
      tableHeaderBackgroundColor:
          tableHeaderBackgroundColor ?? this.tableHeaderBackgroundColor,
      tableRowBackgroundColor:
          tableRowBackgroundColor ?? this.tableRowBackgroundColor,
      selectionColor: selectionColor ?? this.selectionColor,
      quoteBorderWidth: quoteBorderWidth ?? this.quoteBorderWidth,
    );
  }

  @override
  MarkdownThemeData lerp(ThemeExtension<MarkdownThemeData>? other, double t) {
    if (other is! MarkdownThemeData) {
      return this;
    }
    return MarkdownThemeData(
      padding: EdgeInsetsGeometry.lerp(padding, other.padding, t) ?? padding,
      blockSpacing:
          lerpDouble(blockSpacing, other.blockSpacing, t) ?? blockSpacing,
      listItemSpacing: lerpDouble(listItemSpacing, other.listItemSpacing, t) ??
          listItemSpacing,
      maxContentWidth: lerpDouble(maxContentWidth, other.maxContentWidth, t) ??
          maxContentWidth,
      quotePadding:
          EdgeInsetsGeometry.lerp(quotePadding, other.quotePadding, t) ??
              quotePadding,
      inlineCodePadding:
          EdgeInsets.lerp(inlineCodePadding, other.inlineCodePadding, t) ??
              inlineCodePadding,
      codeBlockPadding: EdgeInsetsGeometry.lerp(
            codeBlockPadding,
            other.codeBlockPadding,
            t,
          ) ??
          codeBlockPadding,
      tableCellPadding: EdgeInsetsGeometry.lerp(
            tableCellPadding,
            other.tableCellPadding,
            t,
          ) ??
          tableCellPadding,
      inlineCodeBorderRadius: BorderRadius.lerp(
            inlineCodeBorderRadius,
            other.inlineCodeBorderRadius,
            t,
          ) ??
          inlineCodeBorderRadius,
      codeBlockBorderRadius: BorderRadius.lerp(
            codeBlockBorderRadius,
            other.codeBlockBorderRadius,
            t,
          ) ??
          codeBlockBorderRadius,
      imageBorderRadius: BorderRadius.lerp(
            imageBorderRadius,
            other.imageBorderRadius,
            t,
          ) ??
          imageBorderRadius,
      quoteBorderRadius: BorderRadius.lerp(
            quoteBorderRadius,
            other.quoteBorderRadius,
            t,
          ) ??
          quoteBorderRadius,
      tableBorderRadius: BorderRadius.lerp(
            tableBorderRadius,
            other.tableBorderRadius,
            t,
          ) ??
          tableBorderRadius,
      imageCaptionSpacing:
          lerpDouble(imageCaptionSpacing, other.imageCaptionSpacing, t) ??
              imageCaptionSpacing,
      codeBlockToolbarPadding: EdgeInsetsGeometry.lerp(
            codeBlockToolbarPadding,
            other.codeBlockToolbarPadding,
            t,
          ) ??
          codeBlockToolbarPadding,
      bodyStyle: TextStyle.lerp(bodyStyle, other.bodyStyle, t) ?? bodyStyle,
      quoteStyle: TextStyle.lerp(quoteStyle, other.quoteStyle, t) ?? quoteStyle,
      linkStyle: TextStyle.lerp(linkStyle, other.linkStyle, t) ?? linkStyle,
      inlineCodeStyle:
          TextStyle.lerp(inlineCodeStyle, other.inlineCodeStyle, t) ??
              inlineCodeStyle,
      codeBlockStyle: TextStyle.lerp(codeBlockStyle, other.codeBlockStyle, t) ??
          codeBlockStyle,
      tableHeaderStyle:
          TextStyle.lerp(tableHeaderStyle, other.tableHeaderStyle, t) ??
              tableHeaderStyle,
      heading1Style: TextStyle.lerp(heading1Style, other.heading1Style, t) ??
          heading1Style,
      heading2Style: TextStyle.lerp(heading2Style, other.heading2Style, t) ??
          heading2Style,
      heading3Style: TextStyle.lerp(heading3Style, other.heading3Style, t) ??
          heading3Style,
      heading4Style: TextStyle.lerp(heading4Style, other.heading4Style, t) ??
          heading4Style,
      heading5Style: TextStyle.lerp(heading5Style, other.heading5Style, t) ??
          heading5Style,
      heading6Style: TextStyle.lerp(heading6Style, other.heading6Style, t) ??
          heading6Style,
      quoteBackgroundColor:
          Color.lerp(quoteBackgroundColor, other.quoteBackgroundColor, t) ??
              quoteBackgroundColor,
      quoteBorderColor:
          Color.lerp(quoteBorderColor, other.quoteBorderColor, t) ??
              quoteBorderColor,
      inlineCodeBackgroundColor: Color.lerp(
            inlineCodeBackgroundColor,
            other.inlineCodeBackgroundColor,
            t,
          ) ??
          inlineCodeBackgroundColor,
      codeBlockBackgroundColor: Color.lerp(
            codeBlockBackgroundColor,
            other.codeBlockBackgroundColor,
            t,
          ) ??
          codeBlockBackgroundColor,
      dividerColor:
          Color.lerp(dividerColor, other.dividerColor, t) ?? dividerColor,
      tableBorderColor:
          Color.lerp(tableBorderColor, other.tableBorderColor, t) ??
              tableBorderColor,
      tableHeaderBackgroundColor: Color.lerp(
            tableHeaderBackgroundColor,
            other.tableHeaderBackgroundColor,
            t,
          ) ??
          tableHeaderBackgroundColor,
      tableRowBackgroundColor: Color.lerp(
            tableRowBackgroundColor,
            other.tableRowBackgroundColor,
            t,
          ) ??
          tableRowBackgroundColor,
      selectionColor:
          Color.lerp(selectionColor, other.selectionColor, t) ?? selectionColor,
      quoteBorderWidth:
          lerpDouble(quoteBorderWidth, other.quoteBorderWidth, t) ??
              quoteBorderWidth,
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DoubleProperty('blockSpacing', blockSpacing));
    properties.add(DoubleProperty('listItemSpacing', listItemSpacing));
    properties.add(DoubleProperty('maxContentWidth', maxContentWidth));
    properties.add(DoubleProperty('imageCaptionSpacing', imageCaptionSpacing));
    properties.add(DoubleProperty('quoteBorderWidth', quoteBorderWidth));
    properties.add(ColorProperty('selectionColor', selectionColor));
    properties.add(DiagnosticsProperty<TextStyle>('bodyStyle', bodyStyle));
    properties
        .add(DiagnosticsProperty<TextStyle>('heading1Style', heading1Style));
  }

  @override
  int get hashCode {
    return Object.hashAll(<Object?>[
      padding,
      blockSpacing,
      listItemSpacing,
      maxContentWidth,
      quotePadding,
      inlineCodePadding,
      codeBlockPadding,
      tableCellPadding,
      inlineCodeBorderRadius,
      codeBlockBorderRadius,
      imageBorderRadius,
      quoteBorderRadius,
      tableBorderRadius,
      imageCaptionSpacing,
      codeBlockToolbarPadding,
      bodyStyle,
      quoteStyle,
      linkStyle,
      inlineCodeStyle,
      codeBlockStyle,
      tableHeaderStyle,
      heading1Style,
      heading2Style,
      heading3Style,
      heading4Style,
      heading5Style,
      heading6Style,
      quoteBackgroundColor,
      quoteBorderColor,
      inlineCodeBackgroundColor,
      codeBlockBackgroundColor,
      dividerColor,
      tableBorderColor,
      tableHeaderBackgroundColor,
      tableRowBackgroundColor,
      selectionColor,
      quoteBorderWidth,
    ]);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is MarkdownThemeData &&
        other.padding == padding &&
        other.blockSpacing == blockSpacing &&
        other.listItemSpacing == listItemSpacing &&
        other.maxContentWidth == maxContentWidth &&
        other.quotePadding == quotePadding &&
        other.inlineCodePadding == inlineCodePadding &&
        other.codeBlockPadding == codeBlockPadding &&
        other.tableCellPadding == tableCellPadding &&
        other.inlineCodeBorderRadius == inlineCodeBorderRadius &&
        other.codeBlockBorderRadius == codeBlockBorderRadius &&
        other.imageBorderRadius == imageBorderRadius &&
        other.quoteBorderRadius == quoteBorderRadius &&
        other.tableBorderRadius == tableBorderRadius &&
        other.imageCaptionSpacing == imageCaptionSpacing &&
        other.codeBlockToolbarPadding == codeBlockToolbarPadding &&
        other.bodyStyle == bodyStyle &&
        other.quoteStyle == quoteStyle &&
        other.linkStyle == linkStyle &&
        other.inlineCodeStyle == inlineCodeStyle &&
        other.codeBlockStyle == codeBlockStyle &&
        other.tableHeaderStyle == tableHeaderStyle &&
        other.heading1Style == heading1Style &&
        other.heading2Style == heading2Style &&
        other.heading3Style == heading3Style &&
        other.heading4Style == heading4Style &&
        other.heading5Style == heading5Style &&
        other.heading6Style == heading6Style &&
        other.quoteBackgroundColor == quoteBackgroundColor &&
        other.quoteBorderColor == quoteBorderColor &&
        other.inlineCodeBackgroundColor == inlineCodeBackgroundColor &&
        other.codeBlockBackgroundColor == codeBlockBackgroundColor &&
        other.dividerColor == dividerColor &&
        other.tableBorderColor == tableBorderColor &&
        other.tableHeaderBackgroundColor == tableHeaderBackgroundColor &&
        other.tableRowBackgroundColor == tableRowBackgroundColor &&
        other.selectionColor == selectionColor &&
        other.quoteBorderWidth == quoteBorderWidth;
  }
}
