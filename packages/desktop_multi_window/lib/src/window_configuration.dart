class Rect {
  final double left;
  final double top;
  final double width;
  final double height;

  const Rect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  factory Rect.fromJson(Map<String, dynamic> json) {
    return Rect(
      left: (json['left'] as num).toDouble(),
      top: (json['top'] as num).toDouble(),
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'left': left,
      'top': top,
      'width': width,
      'height': height,
    };
  }

  @override
  String toString() {
    return 'Rect(left: $left, top: $top, width: $width, height: $height)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Rect &&
        other.left == left &&
        other.top == top &&
        other.width == width &&
        other.height == height;
  }

  @override
  int get hashCode {
    return left.hashCode ^ top.hashCode ^ width.hashCode ^ height.hashCode;
  }
}

class WindowConfiguration {
  const WindowConfiguration({
    required this.arguments,
    this.title = '',
    this.frame = const Rect(left: 0, top: 0, width: 800, height: 600),
    this.resizable = true,
    this.hideTitleBar = false,
    this.hiddenAtLaunch = false,
  });

  /// The arguments passed to the new window.
  final String arguments;

  final String title;
  final Rect frame;
  final bool resizable;
  final bool hideTitleBar;
  final bool hiddenAtLaunch;

  factory WindowConfiguration.fromJson(Map<String, dynamic> json) {
    return WindowConfiguration(
      arguments: json['arguments'] as String? ?? '',
      title: json['title'] as String? ?? '',
      frame: json['frame'] != null
          ? Rect.fromJson(json['frame'] as Map<String, dynamic>)
          : const Rect(left: 0, top: 0, width: 800, height: 600),
      resizable: json['resizable'] as bool? ?? true,
      hideTitleBar: json['hideTitleBar'] as bool? ?? false,
      hiddenAtLaunch: json['hiddenAtLaunch'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'arguments': arguments,
      'title': title,
      'frame': frame.toJson(),
      'resizable': resizable,
      'hideTitleBar': hideTitleBar,
      'hiddenAtLaunch': hiddenAtLaunch,
    };
  }

  @override
  String toString() {
    return 'WindowConfiguration(arguments: $arguments, title: $title, frame: $frame, resizable: $resizable, hideTitleBar: $hideTitleBar, hiddenAtLaunch: $hiddenAtLaunch)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WindowConfiguration &&
        other.arguments == arguments &&
        other.title == title &&
        other.frame == frame &&
        other.resizable == resizable &&
        other.hideTitleBar == hideTitleBar &&
        other.hiddenAtLaunch == hiddenAtLaunch;
  }

  @override
  int get hashCode {
    return arguments.hashCode ^
        title.hashCode ^
        frame.hashCode ^
        resizable.hashCode ^
        hideTitleBar.hashCode ^
        hiddenAtLaunch.hashCode;
  }
}
