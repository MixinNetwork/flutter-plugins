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

enum MarkdownThemeForeground {
  light,
  dark,
}

enum MarkdownThemeDensity {
  comfortable,
  tight,
}

@immutable
class _MarkdownThemePalette {
  const _MarkdownThemePalette({
    required this.foreground,
    required this.secondaryForeground,
    required this.headingForeground,
    required this.linkForeground,
    required this.quoteBackgroundColor,
    required this.quoteBorderColor,
    required this.inlineCodeBackgroundColor,
    required this.codeBlockBackgroundColor,
    required this.tableHeaderBackgroundColor,
    required this.tableRowBackgroundColor,
    required this.imagePlaceholderBackgroundColor,
    required this.selectionColor,
    required this.dividerColor,
    required this.tableBorderColor,
  });

  final Color foreground;
  final Color secondaryForeground;
  final Color headingForeground;
  final Color linkForeground;
  final Color quoteBackgroundColor;
  final Color quoteBorderColor;
  final Color inlineCodeBackgroundColor;
  final Color codeBlockBackgroundColor;
  final Color tableHeaderBackgroundColor;
  final Color tableRowBackgroundColor;
  final Color imagePlaceholderBackgroundColor;
  final Color selectionColor;
  final Color dividerColor;
  final Color tableBorderColor;
}

@immutable
class _MarkdownThemeScheme {
  const _MarkdownThemeScheme({
    required this.colorScheme,
    required this.palette,
  });

  final ColorScheme colorScheme;
  final _MarkdownThemePalette palette;
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
    required this.imagePlaceholderBackgroundColor,
    required this.showHeading1Divider,
    required this.showHeading2Divider,
    required this.codeHighlightMaxLines,
  });

  factory MarkdownThemeData.fallback(
    BuildContext context, {
    double maxContentWidth = 920,
  }) {
    return MarkdownThemeData.themed(
      context,
      maxContentWidth: maxContentWidth,
    );
  }

  factory MarkdownThemeData.tight(
    BuildContext context, {
    MarkdownThemeForeground foreground = MarkdownThemeForeground.light,
    double maxContentWidth = 920,
  }) {
    return MarkdownThemeData.themed(
      context,
      foreground: foreground,
      density: MarkdownThemeDensity.tight,
      maxContentWidth: maxContentWidth,
    );
  }

  factory MarkdownThemeData.night(
    BuildContext context, {
    MarkdownThemeDensity density = MarkdownThemeDensity.comfortable,
    double maxContentWidth = 920,
  }) {
    return MarkdownThemeData.themed(
      context,
      foreground: MarkdownThemeForeground.dark,
      density: density,
      maxContentWidth: maxContentWidth,
    );
  }

  factory MarkdownThemeData.themed(
    BuildContext context, {
    MarkdownThemeForeground foreground = MarkdownThemeForeground.light,
    MarkdownThemeDensity density = MarkdownThemeDensity.comfortable,
    double maxContentWidth = 920,
  }) {
    final scheme = MarkdownThemeData._schemeForForeground(context, foreground);
    final comfortableTheme = MarkdownThemeData._fromScheme(
      context,
      colorScheme: scheme.colorScheme,
      palette: scheme.palette,
      maxContentWidth: maxContentWidth,
    );
    return switch (density) {
      MarkdownThemeDensity.comfortable => comfortableTheme,
      MarkdownThemeDensity.tight =>
        MarkdownThemeData._applyTightDensity(comfortableTheme),
    };
  }

  static _MarkdownThemeScheme _schemeForForeground(
    BuildContext context,
    MarkdownThemeForeground foreground,
  ) {
    final theme = Theme.of(context);
    return switch (foreground) {
      MarkdownThemeForeground.light => _lightScheme(theme),
      MarkdownThemeForeground.dark => _darkScheme(theme),
    };
  }

  static _MarkdownThemeScheme _lightScheme(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final borderColor =
        Color.lerp(colorScheme.outline, colorScheme.onSurface, 0.24) ??
            colorScheme.outline;
    return _MarkdownThemeScheme(
      colorScheme: colorScheme,
      palette: _MarkdownThemePalette(
        foreground: colorScheme.onSurface,
        secondaryForeground: colorScheme.onSurface.withValues(alpha: 0.82),
        headingForeground: colorScheme.onSurface,
        linkForeground: colorScheme.primary,
        quoteBackgroundColor: Colors.transparent,
        quoteBorderColor: colorScheme.primary.withValues(alpha: 0.4),
        inlineCodeBackgroundColor: MarkdownThemeData._tintedOverlay(
          colorScheme.onSurface,
          colorScheme.primary,
          mix: 0.18,
          alpha: 0.1,
        ),
        codeBlockBackgroundColor: MarkdownThemeData._tintedOverlay(
          colorScheme.onSurface,
          colorScheme.primary,
          mix: 0.12,
          alpha: 0.12,
        ),
        tableHeaderBackgroundColor: colorScheme.primary.withValues(alpha: 0.11),
        tableRowBackgroundColor: colorScheme.onSurface.withValues(alpha: 0.028),
        imagePlaceholderBackgroundColor: MarkdownThemeData._tintedOverlay(
          colorScheme.onSurface,
          colorScheme.primary,
          mix: 0.1,
          alpha: 0.06,
        ),
        selectionColor: colorScheme.primary.withValues(alpha: 0.24),
        dividerColor: borderColor,
        tableBorderColor: borderColor,
      ),
    );
  }

  static _MarkdownThemeScheme _darkScheme(ThemeData theme) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: theme.colorScheme.primary,
      brightness: Brightness.dark,
    );
    const deepSurface = Color(0xFF0E151D);
    const raisedSurface = Color(0xFF16212C);
    const mutedSurface = Color(0xFF223142);
    const foreground = Color(0xFFE7EDF4);
    const secondaryForeground = Color(0xFFB7C4D3);
    const headingForeground = Color(0xFFF8FBFF);
    const linkForeground = Color(0xFF7CCBFF);
    final borderColor = Color.lerp(colorScheme.outline, foreground, 0.12) ??
        colorScheme.outline;
    return _MarkdownThemeScheme(
      colorScheme: colorScheme,
      palette: _MarkdownThemePalette(
        foreground: foreground,
        secondaryForeground: secondaryForeground,
        headingForeground: headingForeground,
        linkForeground: linkForeground,
        quoteBackgroundColor: Colors.transparent,
        quoteBorderColor: const Color(0xFF4CA7D8),
        inlineCodeBackgroundColor: MarkdownThemeData._tintedOverlay(
          mutedSurface,
          linkForeground,
          mix: 0.12,
          alpha: 0.84,
        ),
        codeBlockBackgroundColor: MarkdownThemeData._tintedOverlay(
          deepSurface,
          linkForeground,
          mix: 0.1,
          alpha: 0.88,
        ),
        tableHeaderBackgroundColor: MarkdownThemeData._tintedOverlay(
          raisedSurface,
          linkForeground,
          mix: 0.22,
          alpha: 0.86,
        ),
        tableRowBackgroundColor: deepSurface.withValues(alpha: 0.74),
        imagePlaceholderBackgroundColor: raisedSurface.withValues(alpha: 0.8),
        selectionColor: const Color(0x664CA7D8),
        dividerColor: borderColor,
        tableBorderColor: borderColor,
      ),
    );
  }

  factory MarkdownThemeData._fromScheme(
    BuildContext context, {
    required ColorScheme colorScheme,
    required _MarkdownThemePalette palette,
    required double maxContentWidth,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final bodyStyle = (textTheme.bodyMedium ?? const TextStyle()).copyWith(
      fontSize: 15,
      color: palette.foreground,
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
      blockSpacing: 14,
      listItemSpacing: 3,
      maxContentWidth: maxContentWidth,
      quotePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      inlineCodePadding:
          const EdgeInsets.symmetric(horizontal: 5, vertical: 0.5),
      codeBlockPadding: const EdgeInsets.all(16),
      tableCellPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      inlineCodeBorderRadius: BorderRadius.circular(6),
      codeBlockBorderRadius: BorderRadius.circular(4),
      imageBorderRadius: BorderRadius.circular(6),
      quoteBorderRadius: BorderRadius.circular(4),
      tableBorderRadius: BorderRadius.circular(6),
      imageCaptionSpacing: 8,
      codeBlockToolbarPadding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
      bodyStyle: bodyStyle,
      quoteStyle: bodyStyle.copyWith(
        fontSize: 15,
        color: palette.foreground.withValues(alpha: 0.72),
      ),
      linkStyle: bodyStyle.copyWith(
        color: palette.linkForeground,
        decoration: TextDecoration.underline,
        decorationColor: palette.linkForeground,
      ),
      inlineCodeStyle: mono,
      codeBlockStyle: mono.copyWith(color: palette.foreground),
      tableHeaderStyle: bodyStyle.copyWith(
        fontWeight: FontWeight.w700,
        color: palette.headingForeground,
      ),
      heading1Style: textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: palette.headingForeground,
          ) ??
          bodyStyle.copyWith(
            fontSize: 34,
            fontWeight: FontWeight.w700,
            color: palette.headingForeground,
          ),
      heading2Style: textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: palette.headingForeground,
          ) ??
          bodyStyle.copyWith(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: palette.headingForeground,
          ),
      heading3Style: textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: palette.headingForeground,
          ) ??
          bodyStyle.copyWith(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: palette.headingForeground,
          ),
      heading4Style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: palette.headingForeground,
          ) ??
          bodyStyle.copyWith(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            color: palette.headingForeground,
          ),
      heading5Style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: palette.headingForeground,
          ) ??
          bodyStyle.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: palette.headingForeground,
          ),
      heading6Style: textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: palette.headingForeground,
          ) ??
          bodyStyle.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: palette.headingForeground,
          ),
      quoteBackgroundColor: palette.quoteBackgroundColor,
      quoteBorderColor: palette.quoteBorderColor,
      inlineCodeBackgroundColor: palette.inlineCodeBackgroundColor,
      codeBlockBackgroundColor: palette.codeBlockBackgroundColor,
      dividerColor: palette.dividerColor,
      tableBorderColor: palette.tableBorderColor,
      tableHeaderBackgroundColor: palette.tableHeaderBackgroundColor,
      tableRowBackgroundColor: palette.tableRowBackgroundColor,
      selectionColor: palette.selectionColor,
      quoteBorderWidth: 4,
      imagePlaceholderBackgroundColor: palette.imagePlaceholderBackgroundColor,
      showHeading1Divider: true,
      showHeading2Divider: true,
      codeHighlightMaxLines: 120,
    );
  }

  static MarkdownThemeData _applyTightDensity(MarkdownThemeData baseTheme) {
    final bodySize = baseTheme.bodyStyle.fontSize ?? 16;
    final codeSize = (bodySize - 1).clamp(14.0, bodySize).toDouble();
    final quoteSize = (bodySize - 1).clamp(14.0, bodySize).toDouble();
    return baseTheme.copyWith(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      blockSpacing: 9,
      listItemSpacing: 1.5,
      quotePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      inlineCodePadding:
          const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
      codeBlockPadding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      tableCellPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      inlineCodeBorderRadius: BorderRadius.circular(5),
      codeBlockBorderRadius: BorderRadius.circular(4),
      tableBorderRadius: BorderRadius.circular(5),
      imageCaptionSpacing: 6,
      codeBlockToolbarPadding: const EdgeInsets.fromLTRB(10, 6, 8, 0),
      quoteStyle: baseTheme.quoteStyle.copyWith(fontSize: quoteSize),
      linkStyle: baseTheme.linkStyle.copyWith(fontSize: bodySize),
      inlineCodeStyle: baseTheme.inlineCodeStyle.copyWith(fontSize: codeSize),
      codeBlockStyle: baseTheme.codeBlockStyle.copyWith(fontSize: codeSize),
      tableHeaderStyle: baseTheme.tableHeaderStyle.copyWith(fontSize: bodySize),
      heading1Style:
          baseTheme.heading1Style.copyWith(fontSize: 30, height: 1.2),
      heading2Style:
          baseTheme.heading2Style.copyWith(fontSize: 25, height: 1.22),
      heading3Style:
          baseTheme.heading3Style.copyWith(fontSize: 21, height: 1.24),
      heading4Style:
          baseTheme.heading4Style.copyWith(fontSize: 18.5, height: 1.26),
      heading5Style:
          baseTheme.heading5Style.copyWith(fontSize: 17, height: 1.28),
      heading6Style:
          baseTheme.heading6Style.copyWith(fontSize: 16, height: 1.3),
    );
  }

  static Color _tintedOverlay(
    Color base,
    Color tint, {
    required double mix,
    required double alpha,
  }) {
    return (Color.lerp(base, tint, mix) ?? tint).withValues(alpha: alpha);
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
  final Color imagePlaceholderBackgroundColor;
  final bool showHeading1Divider;
  final bool showHeading2Divider;
  final int? codeHighlightMaxLines;

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
    Color? imagePlaceholderBackgroundColor,
    bool? showHeading1Divider,
    bool? showHeading2Divider,
    int? codeHighlightMaxLines,
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
      imagePlaceholderBackgroundColor: imagePlaceholderBackgroundColor ??
          this.imagePlaceholderBackgroundColor,
      showHeading1Divider: showHeading1Divider ?? this.showHeading1Divider,
      showHeading2Divider: showHeading2Divider ?? this.showHeading2Divider,
      codeHighlightMaxLines:
          codeHighlightMaxLines ?? this.codeHighlightMaxLines,
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
      imagePlaceholderBackgroundColor: Color.lerp(
            imagePlaceholderBackgroundColor,
            other.imagePlaceholderBackgroundColor,
            t,
          ) ??
          imagePlaceholderBackgroundColor,
      showHeading1Divider:
          t < 0.5 ? showHeading1Divider : other.showHeading1Divider,
      showHeading2Divider:
          t < 0.5 ? showHeading2Divider : other.showHeading2Divider,
      codeHighlightMaxLines:
          t < 0.5 ? codeHighlightMaxLines : other.codeHighlightMaxLines,
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
    properties.add(IntProperty('codeHighlightMaxLines', codeHighlightMaxLines));
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
      imagePlaceholderBackgroundColor,
      showHeading1Divider,
      showHeading2Divider,
      codeHighlightMaxLines,
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
        other.quoteBorderWidth == quoteBorderWidth &&
        other.imagePlaceholderBackgroundColor ==
            imagePlaceholderBackgroundColor &&
        other.showHeading1Divider == showHeading1Divider &&
        other.showHeading2Divider == showHeading2Divider &&
        other.codeHighlightMaxLines == codeHighlightMaxLines;
  }
}
