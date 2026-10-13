import 'package:flutter/material.dart';

// Shared with browser instances, including windows without a Flutter toolbar.
final defaultTitleBarTheme = ValueNotifier<ThemeData?>(null);

// Set while the multi-view application root is mounted. Native initialization
// must complete before a browser requests a view on the application engine.
Future<void>? titleBarInitialization;
