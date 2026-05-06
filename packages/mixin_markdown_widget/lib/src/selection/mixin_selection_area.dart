import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../clipboard/plain_text_serializer.dart';
import '../core/document.dart';
import '../render/pretext_text_block.dart';
import '../render/selectable_block.dart';
import '../render/shortcuts/markdown_shortcuts_scope.dart';
import '../widgets/markdown_theme.dart';
import '../widgets/markdown_types.dart';
import 'selection_controller.dart';
import 'selection_host.dart';
import 'selection_registrar.dart';

typedef MixinSelectionRectResolver = List<Rect> Function(
  BuildContext context,
  Size size,
  DocumentRange range,
);

typedef MixinTextOffsetResolver = int? Function(
  BuildContext context,
  Size size,
  Offset localPosition,
);

typedef MixinSelectionUnitRangeResolver = DocumentRange? Function(
  BuildContext context,
  Size size,
  Offset? localPosition,
  DocumentPosition position,
);

typedef MixinSelectionClipRectResolver = Rect? Function(
  BuildContext context,
  Size size,
);

class MixinSelectionArea extends StatefulWidget {
  const MixinSelectionArea({
    super.key,
    required this.child,
    this.controller,
    this.scrollController,
    this.selectionColor,
    this.contextMenuBuilder,
    this.enableCopyFullDocumentShortcut = true,
    this.showCopyAllInContextMenu = true,
  });

  final Widget child;
  final MarkdownSelectionController? controller;
  final ScrollController? scrollController;
  final Color? selectionColor;
  final MarkdownContextMenuBuilder? contextMenuBuilder;
  final bool enableCopyFullDocumentShortcut;
  final bool showCopyAllInContextMenu;

  @override
  State<MixinSelectionArea> createState() => _MixinSelectionAreaState();
}

class _MixinSelectionAreaState extends State<MixinSelectionArea> {
  final MarkdownPlainTextSerializer _plainTextSerializer =
      const MarkdownPlainTextSerializer();
  final ContextMenuController _contextMenuController = ContextMenuController();
  final GlobalKey _selectionAreaKey =
      GlobalKey(debugLabel: 'mixin-selection-area');
  final ScrollController _fallbackScrollController = ScrollController();
  final Map<Object, MixinSelectionParticipant> _participants =
      <Object, MixinSelectionParticipant>{};
  final Map<Object, int> _registrationOrder = <Object, int>{};
  final Map<Object, int> _blockIndexOffsets = <Object, int>{};
  final Map<Object, int> _blockCounts = <Object, int>{};
  final List<MixinSelectionParticipant> _orderedParticipants =
      <MixinSelectionParticipant>[];

  late final MarkdownSelectionController _fallbackController;
  MarkdownDocument _document = const MarkdownDocument.empty();
  int _nextRegistrationOrder = 0;
  int _documentVersion = 0;
  bool _documentRefreshScheduled = false;

  MarkdownSelectionController get _controller =>
      widget.controller ?? _fallbackController;

  ScrollController get _scrollController =>
      widget.scrollController ?? _fallbackScrollController;

  @override
  void initState() {
    super.initState();
    _fallbackController = MarkdownSelectionController();
  }

  @override
  void didUpdateWidget(covariant MixinSelectionArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _controller.attachDocument(_document);
    }
  }

  @override
  void dispose() {
    _contextMenuController.remove();
    _fallbackScrollController.dispose();
    _fallbackController.dispose();
    super.dispose();
  }

  int? _blockIndexOffsetOf(Object owner) => _blockIndexOffsets[owner];

  void _registerParticipant(MixinSelectionParticipant participant) {
    final owner = participant.owner;
    final wasRegistered = _participants.containsKey(owner);
    _participants[owner] = participant;
    _registrationOrder.putIfAbsent(owner, () => _nextRegistrationOrder++);
    if (wasRegistered) {
      _orderedParticipants
        ..clear()
        ..addAll(_participants.values);
    }
    _scheduleDocumentRefresh();
  }

  void _unregisterParticipant(Object owner) {
    if (_participants.remove(owner) == null) {
      return;
    }
    _registrationOrder.remove(owner);
    _blockIndexOffsets.remove(owner);
    _blockCounts.remove(owner);
    _orderedParticipants
        .removeWhere((participant) => participant.owner == owner);
    _scheduleDocumentRefresh();
  }

  void _participantChanged(Object owner) {
    if (!_participants.containsKey(owner)) {
      return;
    }
    _scheduleDocumentRefresh();
  }

  void _scheduleDocumentRefresh() {
    if (_documentRefreshScheduled) {
      return;
    }
    _documentRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _documentRefreshScheduled = false;
      if (!mounted) {
        return;
      }
      _refreshDocument();
    });
  }

  void _refreshDocument() {
    final orderedParticipants = _participants.values.toList(growable: false)
      ..sort(_compareParticipants);
    final offsets = <Object, int>{};
    final counts = <Object, int>{};
    final blocks = <BlockNode>[];
    for (final participant in orderedParticipants) {
      final participantBlocks = participant.blocks();
      offsets[participant.owner] = blocks.length;
      counts[participant.owner] = participantBlocks.length;
      blocks.addAll(participantBlocks);
    }

    _orderedParticipants
      ..clear()
      ..addAll(orderedParticipants);
    _blockIndexOffsets
      ..clear()
      ..addAll(offsets);
    _blockCounts
      ..clear()
      ..addAll(counts);
    _document = MarkdownDocument(
      blocks: List<BlockNode>.unmodifiable(blocks),
      version: ++_documentVersion,
    );
    _controller.attachDocument(_document);
    setState(() {});
  }

  int _compareParticipants(
    MixinSelectionParticipant a,
    MixinSelectionParticipant b,
  ) {
    final aRect = a.globalRect();
    final bRect = b.globalRect();
    if (aRect != null && bRect != null) {
      final topDelta = aRect.top - bRect.top;
      if (topDelta.abs() > 1.0) {
        return topDelta < 0 ? -1 : 1;
      }
      final leftDelta = aRect.left - bRect.left;
      if (leftDelta.abs() > 1.0) {
        return leftDelta < 0 ? -1 : 1;
      }
    }
    return (_registrationOrder[a.owner] ?? 0)
        .compareTo(_registrationOrder[b.owner] ?? 0);
  }

  void _showToolbar(Offset globalPosition) {
    MarkdownContextMenu.show(
      context,
      contextMenuController: _contextMenuController,
      selectionController: _controller,
      document: _document,
      globalPosition: globalPosition,
      onCopyPlainText: widget.enableCopyFullDocumentShortcut
          ? _copyFullDocumentPlainTextToClipboard
          : null,
      showCopyAllInContextMenu: widget.showCopyAllInContextMenu,
      contextMenuBuilder: widget.contextMenuBuilder,
    );
  }

  void _copyFullDocumentPlainTextToClipboard() {
    Clipboard.setData(
      ClipboardData(text: _plainTextSerializer.serialize(_document)),
    );
  }

  DocumentPosition? _hitTestPosition(
    Offset globalPosition, {
    required bool clamp,
  }) {
    for (final participant in _orderedParticipants) {
      final hit = participant.hitTestPosition(globalPosition, clamp: false);
      if (hit != null) {
        return hit;
      }
    }
    if (!clamp) {
      return null;
    }

    MixinSelectionParticipant? nearestParticipant;
    var bestDistance = double.infinity;
    for (final participant in _orderedParticipants) {
      final rect = participant.globalRect();
      if (rect == null) {
        continue;
      }
      final dx = globalPosition.dx < rect.left
          ? rect.left - globalPosition.dx
          : globalPosition.dx > rect.right
              ? globalPosition.dx - rect.right
              : 0.0;
      final dy = globalPosition.dy < rect.top
          ? rect.top - globalPosition.dy
          : globalPosition.dy > rect.bottom
              ? globalPosition.dy - rect.bottom
              : 0.0;
      final distance = dx * dx + dy * dy;
      if (distance < bestDistance) {
        bestDistance = distance;
        nearestParticipant = participant;
      }
    }
    return nearestParticipant?.hitTestPosition(globalPosition, clamp: true);
  }

  DocumentPosition? _hitTestExactTextPosition(Offset globalPosition) {
    for (final participant in _orderedParticipants) {
      final hit = participant.hitTestExactTextPosition(globalPosition);
      if (hit != null) {
        return hit;
      }
    }
    return null;
  }

  void _selectWordAt(DocumentPosition position) {
    final participant = _participantForBlockIndex(position.blockIndex);
    if (participant == null) {
      _controller.setSelection(
        DocumentSelection(base: position, extent: position),
      );
      return;
    }
    participant.selectWordAt(position);
  }

  void _selectBlockAt(int blockIndex) {
    final participant = _participantForBlockIndex(blockIndex);
    if (participant == null) {
      return;
    }
    participant.selectBlockAt(blockIndex);
  }

  void _selectSelectionUnitAt(
    Offset globalPosition,
    DocumentPosition position,
  ) {
    final participant = _participantForBlockIndex(position.blockIndex);
    if (participant == null) {
      _controller.setSelection(
        DocumentSelection(base: position, extent: position),
      );
      return;
    }
    participant.selectSelectionUnitAt(globalPosition, position);
  }

  MixinSelectionParticipant? _participantForBlockIndex(int blockIndex) {
    for (final participant in _orderedParticipants) {
      final offset = _blockIndexOffsets[participant.owner];
      final count = _blockCounts[participant.owner];
      if (offset == null || count == null) {
        continue;
      }
      if (blockIndex >= offset && blockIndex < offset + count) {
        return participant;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final selectionColor = widget.selectionColor ??
        TextSelectionTheme.of(context).selectionColor ??
        MarkdownTheme.of(context).selectionColor;
    _controller.attachDocument(_document);

    return TextSelectionTheme(
      data: TextSelectionTheme.of(context).copyWith(
        selectionColor: selectionColor,
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final scopedChild = MixinSelectionRegistrar(
            registryOwner: this,
            controller: _controller,
            selectionColor: selectionColor,
            documentVersion: _document.version,
            selection: _controller.selection,
            registerParticipant: _registerParticipant,
            unregisterParticipant: _unregisterParticipant,
            participantChanged: _participantChanged,
            blockIndexOffsetOf: _blockIndexOffsetOf,
            child: widget.child,
          );
          return MarkdownSelectionHost(
            selectionController: _controller,
            document: _document,
            onCopyPlainText: widget.enableCopyFullDocumentShortcut
                ? _copyFullDocumentPlainTextToClipboard
                : null,
            scrollableKey: _selectionAreaKey,
            scrollController: _scrollController,
            onRequestToolbar: _showToolbar,
            hitTestPosition: _hitTestPosition,
            hitTestExactTextPosition: _hitTestExactTextPosition,
            selectWordAt: _selectWordAt,
            selectBlockAt: _selectBlockAt,
            selectSelectionUnitAt: _selectSelectionUnitAt,
            onTapOutside: _contextMenuController.remove,
            child: KeyedSubtree(
              key: _selectionAreaKey,
              child: scopedChild,
            ),
          );
        },
      ),
    );
  }
}

class MixinSelectable extends StatefulWidget {
  const MixinSelectable({
    super.key,
    required this.child,
    required this.plainText,
    this.selectionId,
    this.textSpan,
    this.textAlign = TextAlign.start,
    this.measurementPadding = EdgeInsets.zero,
    this.selectAsBlock = false,
    this.highlightBorderRadius,
    this.selectionRectResolver,
    this.textOffsetResolver,
    this.selectionUnitRangeResolver,
    this.paintSelectionAboveChild = false,
    this.selectionColor,
    this.repaintListenable,
    this.selectionClipPadding,
    this.selectionClipRectResolver,
  });

  final Widget child;
  final String plainText;
  final Object? selectionId;
  final InlineSpan? textSpan;
  final TextAlign textAlign;
  final EdgeInsets measurementPadding;
  final bool selectAsBlock;
  final BorderRadius? highlightBorderRadius;
  final MixinSelectionRectResolver? selectionRectResolver;
  final MixinTextOffsetResolver? textOffsetResolver;
  final MixinSelectionUnitRangeResolver? selectionUnitRangeResolver;
  final bool paintSelectionAboveChild;
  final Color? selectionColor;
  final Listenable? repaintListenable;
  final EdgeInsets? selectionClipPadding;
  final MixinSelectionClipRectResolver? selectionClipRectResolver;

  @override
  State<MixinSelectable> createState() => _MixinSelectableState();
}

class _MixinSelectableState extends State<MixinSelectable> {
  final GlobalKey<SelectableMarkdownBlockState> _blockKey =
      GlobalKey<SelectableMarkdownBlockState>();
  MixinSelectionRegistrar? _registrar;

  Object? get selectionId => widget.selectionId;
  String get plainText => widget.plainText;
  Rect? get globalRect => _blockKey.currentState?.globalRect;

  int? get _blockIndex => _registrar?.blockIndexOffsetOf(this);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextRegistrar = MixinSelectionRegistrar.maybeOf(context);
    if (identical(_registrar?.registryOwner, nextRegistrar?.registryOwner)) {
      _registrar = nextRegistrar;
      return;
    }
    _registrar?.unregisterParticipant(this);
    _registrar = nextRegistrar;
    _registrar?.registerParticipant(_participant());
  }

  @override
  void didUpdateWidget(covariant MixinSelectable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plainText != widget.plainText ||
        oldWidget.selectionId != widget.selectionId) {
      _registrar?.registerParticipant(_participant());
      _registrar?.participantChanged(this);
    }
  }

  @override
  void dispose() {
    _registrar?.unregisterParticipant(this);
    super.dispose();
  }

  MixinSelectionParticipant _participant() {
    return MixinSelectionParticipant(
      owner: this,
      blocks: () {
        final blockIndex = _blockIndex ?? 0;
        final id = widget.selectionId ?? identityHashCode(this);
        return <BlockNode>[
          ParagraphBlock(
            id: 'mixin-selection-$blockIndex-${id.hashCode}',
            inlines: <InlineNode>[
              TextInline(text: widget.plainText),
            ],
          ),
        ];
      },
      globalRect: () => globalRect,
      hitTestPosition: (globalPosition, {required clamp}) {
        return clamp
            ? boundaryPositionForGlobal(globalPosition)
            : hitTestGlobal(globalPosition);
      },
      hitTestExactTextPosition: hitTestTextGlobal,
      selectWordAt: (position) {
        _registrar?.controller.setSelection(selectWord(position));
      },
      selectBlockAt: (blockIndex) {
        _registrar?.controller.setSelection(selectWholeBlock());
      },
      selectSelectionUnitAt: (globalPosition, position) {
        _registrar?.controller.setSelection(
          selectSelectionUnit(position, globalPosition: globalPosition),
        );
      },
    );
  }

  DocumentPosition? hitTestGlobal(Offset globalPosition) {
    if (_blockIndex == null) {
      return null;
    }
    return _blockKey.currentState?.hitTestGlobal(globalPosition);
  }

  DocumentPosition? hitTestTextGlobal(Offset globalPosition) {
    if (_blockIndex == null) {
      return null;
    }
    return _blockKey.currentState?.hitTestTextGlobal(globalPosition);
  }

  DocumentPosition? boundaryPositionForGlobal(Offset globalPosition) {
    if (_blockIndex == null) {
      return null;
    }
    return _blockKey.currentState?.boundaryPositionForGlobal(globalPosition);
  }

  DocumentSelection selectWholeBlock() {
    final blockIndex = _blockIndex;
    if (blockIndex == null) {
      return const DocumentSelection(
        base: DocumentPosition(
          blockIndex: 0,
          path: PathInBlock(<int>[0]),
          textOffset: 0,
        ),
        extent: DocumentPosition(
          blockIndex: 0,
          path: PathInBlock(<int>[0]),
          textOffset: 0,
        ),
      );
    }
    return _blockKey.currentState?.selectWholeBlock() ??
        DocumentSelection(
          base: DocumentPosition(
            blockIndex: blockIndex,
            path: const PathInBlock(<int>[0]),
            textOffset: 0,
          ),
          extent: DocumentPosition(
            blockIndex: blockIndex,
            path: const PathInBlock(<int>[0]),
            textOffset: widget.plainText.length,
          ),
        );
  }

  DocumentSelection selectWord(DocumentPosition position) {
    return _blockKey.currentState?.selectWord(position) ??
        DocumentSelection(base: position, extent: position);
  }

  DocumentSelection selectSelectionUnit(
    DocumentPosition position, {
    Offset? globalPosition,
  }) {
    return _blockKey.currentState?.selectSelectionUnit(
          position,
          globalPosition: globalPosition,
        ) ??
        DocumentSelection(base: position, extent: position);
  }

  @override
  Widget build(BuildContext context) {
    final registrar = MixinSelectionRegistrar.maybeOf(context);
    if (registrar == null) {
      return widget.child;
    }
    if (!identical(_registrar?.registryOwner, registrar.registryOwner)) {
      _registrar?.unregisterParticipant(this);
      _registrar = registrar;
      _registrar?.registerParticipant(_participant());
    } else {
      _registrar = registrar;
    }

    final blockIndex = registrar.blockIndexOffsetOf(this);
    final selectionRange =
        blockIndex == null ? null : registrar.controller.normalizedRange;
    return SelectableMarkdownBlock(
      key: _blockKey,
      blockIndex: blockIndex ?? 0,
      spec: SelectableBlockSpec(
        child: widget.child,
        plainText: widget.plainText,
        hitTestBehavior: widget.selectAsBlock
            ? SelectableBlockHitTestBehavior.block
            : SelectableBlockHitTestBehavior.text,
        textSpan: widget.textSpan,
        textAlign: widget.textAlign,
        measurementPadding: widget.measurementPadding,
        highlightBorderRadius: widget.highlightBorderRadius,
        selectionRectResolver: widget.selectionRectResolver,
        textOffsetResolver: widget.textOffsetResolver,
        selectionUnitRangeResolver: widget.selectionUnitRangeResolver,
        selectionPaintOrder: widget.paintSelectionAboveChild
            ? SelectableBlockSelectionPaintOrder.aboveChild
            : SelectableBlockSelectionPaintOrder.behindChild,
        selectionColor: widget.selectionColor,
        repaintListenable: widget.repaintListenable,
        selectionClipPadding: widget.selectionClipPadding,
        selectionClipRectResolver: widget.selectionClipRectResolver,
      ),
      selectionColor: widget.selectionColor ?? registrar.selectionColor,
      selectionRange: selectionRange,
    );
  }
}

class MixinSelectableText extends StatelessWidget {
  const MixinSelectableText(
    this.data, {
    super.key,
    this.selectionId,
    this.style,
    this.textAlign,
    this.selectionColor,
  });

  final String data;
  final Object? selectionId;
  final TextStyle? style;
  final TextAlign? textAlign;
  final Color? selectionColor;

  @override
  Widget build(BuildContext context) {
    final defaultTextStyle = DefaultTextStyle.of(context);
    final effectiveStyle = style == null
        ? defaultTextStyle.style
        : defaultTextStyle.style.merge(style);
    final effectiveTextAlign =
        textAlign ?? defaultTextStyle.textAlign ?? TextAlign.start;
    final runs = <MarkdownPretextInlineRun>[
      MarkdownPretextInlineRun(text: data, style: effectiveStyle),
    ];

    MarkdownPretextLayoutResult resolveLayout(
      BuildContext context,
      Size size,
    ) {
      final textScaler =
          MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
      return computeMarkdownPretextLayoutFromRuns(
        runs: runs,
        fallbackStyle: effectiveStyle,
        maxWidth: size.width,
        textScaleFactor: textScaler.scale(1.0),
        textAlign: effectiveTextAlign,
        textDirection: Directionality.of(context),
      );
    }

    return MixinSelectable(
      selectionId: selectionId,
      plainText: data,
      selectionColor: selectionColor,
      child: MarkdownPretextTextBlock.rich(
        runs: runs,
        fallbackStyle: effectiveStyle,
        textAlign: effectiveTextAlign,
      ),
      selectionRectResolver: (context, size, range) {
        final layout = resolveLayout(context, size);
        return layout.selectionRectsForRange(
          range,
          textDirection: Directionality.of(context),
        );
      },
      textOffsetResolver: (context, size, localPosition) {
        final layout = resolveLayout(context, size);
        return layout.textOffsetAt(
          localPosition,
          textDirection: Directionality.of(context),
        );
      },
      selectionUnitRangeResolver: (context, size, localPosition, position) {
        final layout = resolveLayout(context, size);
        final lineRange = localPosition == null
            ? layout.lineRangeForTextOffset(position.textOffset)
            : layout.visualLineRangeForLocalPosition(localPosition) ??
                layout.lineRangeForTextOffset(position.textOffset);
        if (lineRange == null) {
          return null;
        }
        return DocumentRange(
          start: DocumentPosition(
            blockIndex: position.blockIndex,
            path: const PathInBlock(<int>[0]),
            textOffset: lineRange.start,
          ),
          end: DocumentPosition(
            blockIndex: position.blockIndex,
            path: const PathInBlock(<int>[0]),
            textOffset: lineRange.end,
          ),
        );
      },
    );
  }
}
