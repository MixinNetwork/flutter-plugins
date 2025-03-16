import 'package:flutter/material.dart';

import 'window_collection_behavior.dart';
import 'window_level.dart';
import 'window_style_mask.dart';
import 'window_type.dart';
import 'window_backing.dart';
import 'title_visibility.dart';
import 'animation_behavior.dart';

extension ColorExtension on Color {
  Map<String, dynamic> toJson() {
    return {
      'red': r,
      'green': g,
      'blue': b,
      'alpha': a,
    };
  }
}

class MacOSWindowOptions {
  // Common properties
  final MacOsWindowType type;
  final MacOsWindowLevel level;
  final Set<int> styleMask;
  final Set<int> collectionBehavior;
  final int left;
  final int top;
  final int width;
  final int height;
  final String title;
  final bool isOpaque;
  final bool hasShadow;
  final bool isMovable;
  final MacOsWindowBacking backing;
  final Color backgroundColor;
  final bool windowButtonVisibility;

  // NSWindow-only properties
  final bool isModal;
  final MacOsTitleVisibility titleVisibility;
  final bool titlebarAppearsTransparent;
  final bool ignoresMouseEvents;
  final bool acceptsMouseMovedEvents;
  final MacOsAnimationBehavior animationBehavior;

  const MacOSWindowOptions({
    this.type = MacOsWindowType.NSWindow,
    this.level = MacOsWindowLevel.normal,
    // Default style mask is arbitrary; typically you’ll override this.
    this.styleMask = const {
      MacOsWindowStyleMask.miniaturizable,
      MacOsWindowStyleMask.closable,
      MacOsWindowStyleMask.resizable,
      MacOsWindowStyleMask.titled,
      MacOsWindowStyleMask.fullSizeContentView,
    },
    this.left = 10,
    this.top = 10,
    this.width = 1280,
    this.height = 720,
    this.title = '',
    this.isOpaque = true,
    this.hasShadow = true,
    this.isMovable = true,
    this.backing = MacOsWindowBacking.buffered,
    this.backgroundColor = const Color(0x00000000),
    this.windowButtonVisibility = true,
    // NSWindow-specific defaults:
    this.isModal = false,
    this.titleVisibility = MacOsTitleVisibility.visible,
    this.titlebarAppearsTransparent = false,
    this.collectionBehavior = const {MacOsWindowCollectionBehavior.default_},
    this.ignoresMouseEvents = false,
    this.acceptsMouseMovedEvents = false,
    this.animationBehavior = MacOsAnimationBehavior.defaultBehavior,
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
    Set<int> styleMask = const {
      MacOsWindowStyleMask.titled,
      MacOsWindowStyleMask.closable,
      MacOsWindowStyleMask.miniaturizable,
      MacOsWindowStyleMask.utility
    },
    MacOsWindowLevel level = MacOsWindowLevel.floating,
    int left = 10,
    int top = 10,
    int width = 1280,
    int height = 720,
    String title = '',
    Color backgroundColor = const Color(0x00000000),
    bool windowButtonVisibility = true,
    // NSPanel-specific: force non-modal, hide title.
    MacOsWindowBacking backing = MacOsWindowBacking.buffered,
    bool isOpaque = true,
    bool hasShadow = true,
    bool isMovable = true,
    // For panels, we force title to be hidden.
    MacOsTitleVisibility titleVisibility = MacOsTitleVisibility.hidden,
    bool titlebarAppearsTransparent = false,
    Set<int> collectionBehavior = const {
      MacOsWindowCollectionBehavior.default_
    },
    bool ignoresMouseEvents = false,
    bool acceptsMouseMovedEvents = false,
    MacOsAnimationBehavior animationBehavior =
        MacOsAnimationBehavior.defaultBehavior,
  }) {
    if (!styleMask.contains(MacOsWindowStyleMask.utility)) {
      styleMask.add(MacOsWindowStyleMask.utility);
    }
    return MacOSWindowOptions(
      type: MacOsWindowType.NSPanel,
      level: level,
      styleMask: styleMask,
      left: left,
      top: top,
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
      MacOsWindowStyleMask.miniaturizable,
      MacOsWindowStyleMask.closable,
      MacOsWindowStyleMask.resizable,
      MacOsWindowStyleMask.titled,
      MacOsWindowStyleMask.fullSizeContentView,
    },
    MacOsWindowLevel level = MacOsWindowLevel.normal,
    int left = 10,
    int top = 10,
    int width = 1280,
    int height = 720,
    String title = '',
    bool isModal = false,
    bool isOpaque = true,
    MacOsWindowBacking backing = MacOsWindowBacking.buffered,
    Color backgroundColor = const Color(0x00000000),
    bool windowButtonVisibility = true,
    bool hasShadow = true,
    bool isMovable = true,
    MacOsTitleVisibility titleVisibility = MacOsTitleVisibility.visible,
    bool titlebarAppearsTransparent = false,
    Set<int> collectionBehavior = const {
      MacOsWindowCollectionBehavior.default_
    },
    bool ignoresMouseEvents = false,
    bool acceptsMouseMovedEvents = false,
    MacOsAnimationBehavior animationBehavior =
        MacOsAnimationBehavior.defaultBehavior,
  }) {
    return MacOSWindowOptions(
      type: MacOsWindowType.NSWindow,
      level: level,
      styleMask: styleMask,
      left: left,
      top: top,
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
    return {
      'type': type.name,
      'level': level.value,
      'styleMask': styleMask.fold<int>(0, (a, b) => a | b),
      'collectionBehavior': collectionBehavior.fold<int>(0, (a, b) => a | b),
      'left': left,
      'top': top,
      'width': width,
      'height': height,
      'title': title,
      'isOpaque': isOpaque,
      'hasShadow': hasShadow,
      'isMovable': isMovable,
      'backing': backing.value,
      'backgroundColor': backgroundColor.toJson(),
      'windowButtonVisibility': windowButtonVisibility,

        'isModal': isModal,
        'titleVisibility': titleVisibility.value,
        'titlebarAppearsTransparent': titlebarAppearsTransparent,
        'ignoresMouseEvents': ignoresMouseEvents,
        'acceptsMouseMovedEvents': acceptsMouseMovedEvents,
        'animationBehavior': animationBehavior.value,
      };
  }
}
