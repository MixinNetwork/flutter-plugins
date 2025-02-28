import 'package:flutter/material.dart';

import 'window_level.dart';
import 'window_style_mask.dart';
import 'window_type.dart';
import 'window_backing.dart';
import 'title_visibility.dart';
import 'animation_behavior.dart';

extension ColorExtension on Color {
  Map<String, dynamic> toJson() {
    return {
      'red': red,
      'green': green,
      'blue': blue,
      'alpha': alpha,
    };
  }
}

class MacOSWindowOptions {
  // Common properties
  final MacOSWindowType type;
  final MacOSWindowLevel level;
  final Set<int> styleMask;
  final int x;
  final int y;
  final int width;
  final int height;
  final String title;
  final bool isOpaque;
  final bool hasShadow;
  final bool isMovable;
  final MacOSWindowBacking backing;
  final Color backgroundColor;
  final bool windowButtonVisibility;

  // NSWindow-only properties
  final bool isModal;
  final MacOSTitleVisibility titleVisibility;
  final bool titlebarAppearsTransparent;
  final int collectionBehavior;
  final bool ignoresMouseEvents;
  final bool acceptsMouseMovedEvents;
  final MacOSAnimationBehavior animationBehavior;

  const MacOSWindowOptions({
    this.type = MacOSWindowType.NSWindow,
    this.level = MacOSWindowLevel.normal,
    // Default style mask is arbitrary; typically you’ll override this.
    this.styleMask = const {
      MacOSWindowStyleMask.miniaturizable,
      MacOSWindowStyleMask.closable,
      MacOSWindowStyleMask.resizable,
      MacOSWindowStyleMask.titled,
      MacOSWindowStyleMask.fullSizeContentView,
    },
    this.x = 10,
    this.y = 10,
    this.width = 1280,
    this.height = 720,
    this.title = '',
    this.isOpaque = true,
    this.hasShadow = true,
    this.isMovable = true,
    this.backing = MacOSWindowBacking.buffered,
    this.backgroundColor = const Color(0x00000000),
    this.windowButtonVisibility = true,
    // NSWindow-specific defaults:
    this.isModal = false,
    this.titleVisibility = MacOSTitleVisibility.visible,
    this.titlebarAppearsTransparent = false,
    this.collectionBehavior = 0,
    this.ignoresMouseEvents = false,
    this.acceptsMouseMovedEvents = false,
    this.animationBehavior = MacOSAnimationBehavior.defaultBehavior,
  }); /* : assert(
          type != MacOSWindowType.NSPanel || (styleMask & MacOSWindowStyleMask.utility) != 0,
          'NSPanel requires the utility style mask to be set.',
        ),
        assert(
          type != MacOSWindowType.NSPanel || isModal == false,
          'NSPanel cannot be modal.',
        ),
        assert(
          type != MacOSWindowType.NSPanel || titleVisibility == MacOSTitleVisibility.hidden,
          'NSPanel should not have a visible title.',
        ),
        assert(
          type != MacOSWindowType.NSPanel || collectionBehavior == 0,
          'NSPanel does not support collectionBehavior.',
        );*/

  /// Convenience factory constructor for NSPanel.
  factory MacOSWindowOptions.nspanel({
    Set<int> styleMask = const {MacOSWindowStyleMask.titled, MacOSWindowStyleMask.closable, MacOSWindowStyleMask.miniaturizable, MacOSWindowStyleMask.utility},
    MacOSWindowLevel level = MacOSWindowLevel.floating,
    int x = 10,
    int y = 10,
    int width = 1280,
    int height = 720,
    String title = '',
    Color backgroundColor = const Color(0x00000000),
    bool windowButtonVisibility = true,
    // NSPanel-specific: force non-modal, hide title.
    MacOSWindowBacking backing = MacOSWindowBacking.buffered,
    bool isOpaque = true,
    bool hasShadow = true,
    bool isMovable = true,
    // For panels, we force title to be hidden.
    MacOSTitleVisibility titleVisibility = MacOSTitleVisibility.hidden,
    bool titlebarAppearsTransparent = false,
    int collectionBehavior = 0,
    bool ignoresMouseEvents = false,
    bool acceptsMouseMovedEvents = false,
    MacOSAnimationBehavior animationBehavior = MacOSAnimationBehavior.defaultBehavior,
  }) {
    if (!styleMask.contains(MacOSWindowStyleMask.utility)) {
      styleMask.add(MacOSWindowStyleMask.utility);
    }
    return MacOSWindowOptions(
      type: MacOSWindowType.NSPanel,
      level: level,
      styleMask: styleMask,
      x: x,
      y: y,
      width: width,
      height: height,
      title: title,
      isOpaque: isOpaque,
      hasShadow: hasShadow,
      isMovable: isMovable,
      backing: backing,
      backgroundColor: backgroundColor,
      windowButtonVisibility: windowButtonVisibility,
      // Enforce NSPanel restrictions:
      isModal: false,
      titleVisibility: titleVisibility,
      titlebarAppearsTransparent: titlebarAppearsTransparent,
      collectionBehavior: collectionBehavior,
      ignoresMouseEvents: ignoresMouseEvents,
      acceptsMouseMovedEvents: acceptsMouseMovedEvents,
      animationBehavior: animationBehavior,
    );
  }

  /// Convenience factory constructor for NSWindow.
  factory MacOSWindowOptions.nswindow({
    Set<int> styleMask = const {
      MacOSWindowStyleMask.miniaturizable,
      MacOSWindowStyleMask.closable,
      MacOSWindowStyleMask.resizable,
      MacOSWindowStyleMask.titled,
      MacOSWindowStyleMask.fullSizeContentView,
    },
    MacOSWindowLevel level = MacOSWindowLevel.normal,
    int x = 10,
    int y = 10,
    int width = 1280,
    int height = 720,
    String title = '',
    bool isModal = false,
    bool isOpaque = true,
    MacOSWindowBacking backing = MacOSWindowBacking.buffered,
    Color backgroundColor = const Color(0x00000000),
    bool windowButtonVisibility = true,
    bool hasShadow = true,
    bool isMovable = true,
    MacOSTitleVisibility titleVisibility = MacOSTitleVisibility.visible,
    bool titlebarAppearsTransparent = false,
    int collectionBehavior = 0,
    bool ignoresMouseEvents = false,
    bool acceptsMouseMovedEvents = false,
    MacOSAnimationBehavior animationBehavior = MacOSAnimationBehavior.defaultBehavior,
  }) {
    return MacOSWindowOptions(
      type: MacOSWindowType.NSWindow,
      level: level,
      styleMask: styleMask,
      x: x,
      y: y,
      width: width,
      height: height,
      title: title,
      isModal: isModal,
      isOpaque: isOpaque,
      backing: backing,
      backgroundColor: backgroundColor,
      windowButtonVisibility: windowButtonVisibility,
      hasShadow: hasShadow,
      isMovable: isMovable,
      titleVisibility: titleVisibility,
      titlebarAppearsTransparent: titlebarAppearsTransparent,
      collectionBehavior: collectionBehavior,
      ignoresMouseEvents: ignoresMouseEvents,
      acceptsMouseMovedEvents: acceptsMouseMovedEvents,
      animationBehavior: animationBehavior,
    );
  }

  /// Converts the window options to a JSON-compatible map.
  /// The resulting map only includes the keys that are allowed for the specified [type].
  Map<String, dynamic> toJson() {
    // Common properties for both NSWindow and NSPanel.
    final common = {
      'level': level.value,
      'styleMask': styleMask.fold<int>(0, (a, b) => a | b),
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'title': title,
      'isOpaque': isOpaque,
      'hasShadow': hasShadow,
      'isMovable': isMovable,
      'backing': backing.value,
      'backgroundColor': backgroundColor.toJson(),
      'windowButtonVisibility': windowButtonVisibility,
    };

    if (type == MacOSWindowType.NSWindow) {
      return {
        'type': 'NSWindow',
        ...common,
        'isModal': isModal,
        'titleVisibility': titleVisibility.value,
        'titlebarAppearsTransparent': titlebarAppearsTransparent,
        'collectionBehavior': collectionBehavior,
        'ignoresMouseEvents': ignoresMouseEvents,
        'acceptsMouseMovedEvents': acceptsMouseMovedEvents,
        'animationBehavior': animationBehavior.value,
      };
    } else if (type == MacOSWindowType.NSPanel) {
      // For NSPanel, output only the common properties plus any NSPanel-specific ones.
      // We exclude NSWindow-only properties like isModal, titleVisibility, etc.
      return {
        'type': 'NSPanel',
        ...common,
      };
    }
    return common;
  }
}
