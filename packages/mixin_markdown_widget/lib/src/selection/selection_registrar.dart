import 'package:flutter/material.dart';

import '../core/document.dart';
import '../render/selection/markdown_selection_gesture_detector.dart';
import 'selection_controller.dart';

typedef MixinSelectionParticipantHitTest = DocumentPosition? Function(
  Offset globalPosition, {
  required bool clamp,
});

typedef MixinSelectionParticipantExactHitTest = DocumentPosition? Function(
  Offset globalPosition,
);

typedef MixinSelectionParticipantSelectWord = void Function(
  DocumentPosition position,
);

typedef MixinSelectionParticipantSelectBlock = void Function(
  int blockIndex,
);

typedef MixinSelectionParticipantSelectUnit = void Function(
  Offset globalPosition,
  DocumentPosition position,
);

class MixinSelectionParticipant {
  const MixinSelectionParticipant({
    required this.owner,
    required this.blocks,
    required this.globalRect,
    required this.hitTestPosition,
    required this.hitTestExactTextPosition,
    required this.selectWordAt,
    required this.selectBlockAt,
    required this.selectSelectionUnitAt,
    this.autoScrollTargets,
  });

  final Object owner;
  final List<BlockNode> Function() blocks;
  final Rect? Function() globalRect;
  final MixinSelectionParticipantHitTest hitTestPosition;
  final MixinSelectionParticipantExactHitTest hitTestExactTextPosition;
  final MixinSelectionParticipantSelectWord selectWordAt;
  final MixinSelectionParticipantSelectBlock selectBlockAt;
  final MixinSelectionParticipantSelectUnit selectSelectionUnitAt;
  final Iterable<MarkdownSelectionAutoScrollTarget> Function()?
      autoScrollTargets;
}

class MixinSelectionRegistrar extends InheritedWidget {
  const MixinSelectionRegistrar({
    super.key,
    required this.registryOwner,
    required this.controller,
    required this.selectionColor,
    required this.documentVersion,
    required this.selection,
    required this.registerParticipant,
    required this.unregisterParticipant,
    required this.participantChanged,
    required this.blockIndexOffsetOf,
    required super.child,
  });

  final Object registryOwner;
  final MarkdownSelectionController controller;
  final Color selectionColor;
  final int documentVersion;
  final DocumentSelection? selection;
  final void Function(MixinSelectionParticipant participant)
      registerParticipant;
  final void Function(Object owner) unregisterParticipant;
  final void Function(Object owner) participantChanged;
  final int? Function(Object owner) blockIndexOffsetOf;

  static MixinSelectionRegistrar? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<MixinSelectionRegistrar>();
  }

  @override
  bool updateShouldNotify(covariant MixinSelectionRegistrar oldWidget) {
    return oldWidget.controller != controller ||
        oldWidget.selectionColor != selectionColor ||
        oldWidget.documentVersion != documentVersion ||
        oldWidget.selection != selection;
  }
}
