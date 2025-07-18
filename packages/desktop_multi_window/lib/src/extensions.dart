import 'dart:ui';

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