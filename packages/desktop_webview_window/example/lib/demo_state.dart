import 'dart:async';
import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/material.dart';

import 'demo_page_server.dart';

class DemoWindow {
  DemoWindow(this.id, this.webview, this.url);
  final int id;
  final Webview webview;
  String url;
  bool canGoBack = false;
  bool canGoForward = false;
  bool busy = false;
  String result = 'Execute JavaScript or read cookies to see the result here.';
  late final VoidCallback navigationListener;
  late final OnWebMessageReceivedCallback messageListener;
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
  final darkMode = ValueNotifier(false);

  ThemeData get theme => ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: darkMode.value ? Brightness.dark : Brightness.light,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          isDense: true,
        ),
      );
  final windows = <DemoWindow>[];
  final events = <DemoEvent>[];
  int? selectedId;
  int _nextId = 0;
  bool creating = false;
  bool? available;
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

  Future<void> open({
    String? url,
    int count = 1,
    bool showTitleBar = true,
    bool showSystemTitleBar = true,
    bool openHidden = false,
    bool denyMedia = false,
  }) async {
    if (creating || _disposed) return;
    if (url != null) {
      final uri = Uri.tryParse(url);
      if (uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty) {
        log('Enter a valid http:// or https:// URL');
        return;
      }
    }
    creating = true;
    _changed();
    try {
      for (var i = 0; i < count && !_disposed; i++) {
        final id = ++_nextId;
        final view = await WebviewWindow.create(
          configuration: CreateConfiguration(
            title: 'Browser $id',
            windowWidth: 960,
            windowHeight: 720,
            titleBarHeight: showTitleBar ? 44 : 0,
            showSystemTitleBar: showSystemTitleBar,
            titleBarTopPadding:
                showTitleBar && showSystemTitleBar && Platform.isMacOS ? 24 : 0,
            userDataFolderWindows: userDataFolder,
            openHidden: openHidden,
            denyCameraAndMicrophone: denyMedia,
          ),
        );
        if (_disposed) {
          view.close();
          break;
        }
        final window = DemoWindow(id, view, url ?? pages.url(id));
        windows.add(window);
        selectedId = id;
        window.navigationListener = () =>
            log(view.isNavigating.value ? 'Loading' : 'Loading finished', id);
        window.messageListener = (message) => log('Page message: $message', id);
        view.isNavigating.addListener(window.navigationListener);
        view.setOnHistoryChangedCallback((back, forward) {
          window.canGoBack = back;
          window.canGoForward = forward;
          _changed();
        });
        view.setOnUrlRequestCallback((value) {
          window.url = value;
          log('Navigate: $value', id);
          return true;
        });
        if (Platform.isWindows) {
          view.addOnWebMessageReceivedCallback(window.messageListener);
        } else {
          view.registerJavaScriptMessageHandler(
              'demo', (name, body) => log('Page message: $body', id));
        }
        if (Platform.isMacOS) {
          view.setPromptHandler((prompt, text) {
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
        log(openHidden ? 'Created hidden window' : 'Created window', id);
        await perform(window, 'Set user agent', () async {
          await view.setApplicationNameForUserAgent(' WebviewExample/1.0');
          return null;
        });
        if (!_disposed && windows.contains(window)) view.launch(window.url);
      }
    } catch (error) {
      log('Create failed: $error');
    } finally {
      creating = false;
      _changed();
    }
  }

  Future<void> perform(DemoWindow window, String label,
      Future<Object?> Function() action) async {
    if (_disposed || window.busy || !windows.contains(window)) return;
    window.busy = true;
    _changed();
    try {
      final result = await action();
      if (!_disposed && windows.contains(window)) {
        window.result = '$label\n${result ?? 'Done'}';
        log('$label: ${result ?? 'Done'}', window.id);
      }
    } catch (error) {
      if (!_disposed && windows.contains(window)) {
        window.result = '$label failed: $error';
        log(window.result, window.id);
      }
    } finally {
      window.busy = false;
      _changed();
    }
  }

  void _detach(DemoWindow window) {
    window.webview.isNavigating.removeListener(window.navigationListener);
    window.webview.setOnHistoryChangedCallback(null);
    window.webview.setOnUrlRequestCallback(null);
    window.webview.removeOnWebMessageReceivedCallback(window.messageListener);
  }

  @override
  void dispose() {
    _disposed = true;
    for (final window in windows) {
      _detach(window);
      window.webview.close();
    }
    darkMode.dispose();
    unawaited(pages.close());
    super.dispose();
  }
}
