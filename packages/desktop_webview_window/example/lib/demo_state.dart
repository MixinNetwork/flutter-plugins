import 'dart:async';
import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'demo_page_server.dart';

/// How the native window around the page is composed.
enum DemoLayout {
  /// The plugin's default composer, with controls in the native title bar.
  titleBar('Title bar'),

  /// The example runner's native composer, with controls left of the page.
  sidebar('Sidebar composer');

  const DemoLayout(this.label);
  final String label;
}

/// Options chosen in the New window dialog.
class DemoWindowOptions {
  const DemoWindowOptions({
    this.url,
    this.layout = DemoLayout.titleBar,
    this.titleBar = const TitleBarOptions(),
    this.openHidden = false,
    this.denyMedia = false,
  });

  /// Null opens the built-in demo page.
  final String? url;
  final DemoLayout layout;
  final TitleBarOptions titleBar;
  final bool openHidden;
  final bool denyMedia;
}

/// Panels of the window inspector. Each keeps its own latest result.
enum DemoPanel { messages, javascript, cookies, window }

class DemoWindow {
  DemoWindow(this.id, this.webview, this.url, this.options);
  final int id;
  final Webview webview;
  final DemoWindowOptions options;
  String url;
  bool busy = false;
  final results = <DemoPanel, String>{};
  List<WebviewCookie>? cookies;
  ThemeMode appearance = ThemeMode.system;
  late final VoidCallback navigationListener;
  bool _wasLoading = false;

  WebviewNavigationState get navigation => webview.navigationState.value;
  String get currentUrl => navigation.url ?? url;
  String get name => 'Browser $id';
}

class DemoEvent {
  DemoEvent(this.windowId, this.message) : time = DateTime.now();
  final int? windowId;
  final String message;
  final DateTime time;
}

class DemoState extends ChangeNotifier {
  DemoState(this.pages, {this.userDataFolder = 'webview_window_WebView2'});

  final DemoPageServer pages;
  final String userDataFolder;
  final windows = <DemoWindow>[];
  final events = <DemoEvent>[];
  int? selectedId;
  int _nextId = 0;
  bool creating = false;
  bool? available;
  ThemeMode themeMode = ThemeMode.system;
  bool _disposed = false;

  DemoWindow? get selected {
    for (final window in windows) {
      if (window.id == selectedId) return window;
    }
    return null;
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void log(String message, [int? id]) {
    if (_disposed) return;
    final summary = message.replaceAll('\n', ' ');
    events.add(DemoEvent(
        id, summary.length > 200 ? '${summary.substring(0, 200)}…' : summary));
    if (events.length > 200) events.removeAt(0);
    _changed();
  }

  Future<void> initialize() async {
    try {
      available = await WebviewWindow.isWebviewAvailable();
      log(available! ? 'Browser runtime ready' : 'Browser runtime unavailable');
    } catch (error) {
      available = false;
      log('Runtime check failed: $error');
    }
  }

  void select(DemoWindow window) {
    selectedId = window.id;
    _changed();
  }

  void clearEvents() {
    events.clear();
    _changed();
  }

  Brightness? get _brightness => switch (themeMode) {
        ThemeMode.dark => Brightness.dark,
        ThemeMode.light => Brightness.light,
        ThemeMode.system => null,
      };

  /// The app menu overrides every browser, including any per-window choice.
  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    _changed();
    if (Platform.isLinux) {
      try {
        // GTK's appearance is app-wide, unlike the per-window APIs on Cocoa
        // and WebView2. This also updates existing WebKit media queries.
        await const MethodChannel('webview_example/native_test').invokeMethod(
            'setAppTheme', {'brightness': _brightness?.index ?? -1});
        for (final window in windows) {
          if (themeMode == mode) window.appearance = mode;
        }
      } catch (error) {
        log('App theme failed: $error');
      }
    } else {
      await Future.wait(List.of(windows).map((window) async {
        try {
          await window.webview.setBrightness(_brightness);
          if (themeMode == mode) window.appearance = mode;
        } catch (error) {
          if (windows.contains(window)) {
            log('Appearance failed: $error', window.id);
          }
        }
      }));
    }
    _changed();
  }

  /// Accepts `mixin.one` as `https://mixin.one`; null when not http(s).
  static String? normalizeUrl(String input) {
    final text = input.trim();
    final uri = Uri.tryParse(text.contains('://') ? text : 'https://$text');
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      return null;
    }
    return uri.toString();
  }

  Future<void> open(
      [DemoWindowOptions options = const DemoWindowOptions()]) async {
    if (creating || _disposed) return;
    final custom = options.url == null ? null : normalizeUrl(options.url!);
    if (options.url != null && custom == null) {
      log('Enter a valid http:// or https:// URL');
      return;
    }
    creating = true;
    _changed();
    try {
      final id = ++_nextId;
      final initialTheme = themeMode;
      final view = await WebviewWindow.create(
        configuration: CreateConfiguration(
          title: 'Browser $id',
          windowWidth: 960,
          windowHeight: 720,
          titleBar: options.titleBar,
          composerArguments:
              options.layout == DemoLayout.sidebar ? 'sidebar' : null,
          openHidden: options.openHidden,
          brightness: _brightness,
          windows: WindowsWebviewOptions(
            userDataFolder: userDataFolder,
            denyCameraAndMicrophone: options.denyMedia,
          ),
        ),
      );
      if (_disposed) {
        view.close();
        return;
      }
      final window = DemoWindow(id, view, custom ?? pages.url(id), options);
      window.appearance = themeMode;
      windows.add(window);
      selectedId = id;
      window.navigationListener = () {
        final loading = view.navigationState.value.isLoading;
        if (loading != window._wasLoading) {
          window._wasLoading = loading;
          log(loading ? 'Loading' : 'Loading finished', id);
        }
        _changed();
      };
      view.navigationState.addListener(window.navigationListener);
      view.setOnUrlRequestCallback((value) {
        // Applications handle their own schemes, such as mixin:, here.
        final scheme = Uri.tryParse(value)?.scheme ?? '';
        if (!const ['http', 'https', 'file', 'about', 'data']
            .contains(scheme)) {
          log('Application link: $value', id);
          return false;
        }
        window.url = value;
        log('Navigate: $value', id);
        return true;
      });
      view.addJavaScriptHandler('demo', (data) {
        window.results[DemoPanel.messages] = 'Page → Flutter\n$data';
        log('Page message: $data', id);
      });
      if (Platform.isMacOS) {
        view.setPromptHandler((prompt, text) {
          window.results[DemoPanel.messages] = 'Page prompt\n$prompt ($text)';
          log('Prompt: $prompt ($text)', id);
          return 'Hello from Flutter: $text';
        });
      }
      unawaited(view.onClose.then((_) {
        _detach(window);
        windows.remove(window);
        if (selectedId == id) {
          selectedId = windows.isEmpty ? null : windows.last.id;
        }
        log('Closed', id);
      }));
      // A cold WebView2 create can span a theme change in the app menu.
      if (initialTheme != themeMode && !Platform.isLinux) {
        await view.setBrightness(_brightness);
      }
      log(
          '${options.openHidden ? 'Created hidden window' : 'Created window'}'
          ' · ${options.layout.label}',
          id);
      await perform(window, DemoPanel.window, 'Set user agent', () async {
        await view.setApplicationNameForUserAgent(' WebviewExample/1.0');
        return null;
      });
      if (!_disposed && windows.contains(window)) {
        await view.launch(window.url);
      }
    } catch (error) {
      log('Create failed: $error');
    } finally {
      creating = false;
      _changed();
    }
  }

  /// Loads [input] in [window]; returns false when it is not an http(s) URL.
  bool navigate(DemoWindow window, String input) {
    final url = normalizeUrl(input);
    if (url == null) {
      log('Enter a valid http:// or https:// URL', window.id);
      return false;
    }
    unawaited(perform(window, DemoPanel.window, 'Open $url', () async {
      await window.webview.launch(url);
      return null;
    }));
    return true;
  }

  /// Runs [action] for [window] and keeps the outcome in [panel], so a result
  /// stays with the window and panel it came from.
  Future<void> perform(DemoWindow window, DemoPanel panel, String label,
      Future<Object?> Function() action) async {
    if (_disposed || window.busy || !windows.contains(window)) return;
    window.busy = true;
    _changed();
    try {
      final result = await action();
      if (!_disposed && windows.contains(window)) {
        window.results[panel] = '$label\n${result ?? 'Done'}';
        log('$label: ${result ?? 'Done'}', window.id);
      }
    } catch (error) {
      if (!_disposed && windows.contains(window)) {
        window.results[panel] = '$label failed\n$error';
        log('$label failed: $error', window.id);
      }
    } finally {
      window.busy = false;
      _changed();
    }
  }

  Future<void> readCookies(DemoWindow window) =>
      perform(window, DemoPanel.cookies, 'Read cookies', () async {
        final cookies = await window.webview.getAllCookies();
        window.cookies = cookies;
        return '${cookies.length} cookie${cookies.length == 1 ? '' : 's'}';
      });

  void _detach(DemoWindow window) {
    window.webview.navigationState.removeListener(window.navigationListener);
  }

  @override
  void dispose() {
    _disposed = true;
    for (final window in windows) {
      _detach(window);
      unawaited(window.webview.close());
    }
    unawaited(pages.close());
    super.dispose();
  }
}
