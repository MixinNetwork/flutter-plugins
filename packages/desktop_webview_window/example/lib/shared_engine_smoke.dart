import 'dart:async';
import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/material.dart';

// Serve test pages on loopback, preserving native navigation scheme policies.
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!const bool.fromEnvironment('SMOKE_NO_TITLEBAR_HOOK') &&
      runWebViewTitleBarWidget(args)) {
    return;
  }
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final id = request.uri.queryParameters['id'] ?? '0';
    final next = request.uri.path == '/next';
    request.response.headers.contentType = ContentType.html;
    request.response.write(
        '''<!doctype html><title>Browser $id${next ? ' next' : ''}</title>
<h1>Browser $id${next ? ' next' : ''}</h1>
<label>Native input <input placeholder="Type here"></label>
<p>Resize, focus, select text and close this window independently.</p>
<button onclick="this.textContent='Clicked browser $id'">Native button</button>
<a href="${next ? '/' : '/next'}?id=$id">${next ? 'First page' : 'Next page'}</a>''');
    await request.response.close();
  });
  runApp(MaterialApp(home: _SmokePage(port: server.port)));
}

class _SmokePage extends StatefulWidget {
  const _SmokePage({required this.port});
  final int port;

  @override
  State<_SmokePage> createState() => _SmokePageState();
}

class _SmokePageState extends State<_SmokePage> {
  final _open = <Webview>[];
  final _lines = <String>[];
  bool _running = false;
  int _next = 0;

  @override
  void initState() {
    super.initState();
    if (const bool.fromEnvironment('SMOKE_OPEN_PAIR')) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openPair());
    }
  }

  Future<void> _openPair() async {
    try {
      await _create();
      await _create();
    } catch (error) {
      _log('FAIL opening pair: $error');
    }
  }

  void _log(String message) {
    debugPrint('WEBVIEW_SMOKE $message');
    if (mounted) setState(() => _lines.add(message));
  }

  Future<Webview> _create({bool hiddenToolbar = false}) async {
    final id = ++_next;
    final view = await WebviewWindow.create(
      configuration: CreateConfiguration(
        title: 'Browser $id',
        windowWidth: 640,
        windowHeight: 480,
        titleBarHeight: hiddenToolbar ? 0 : 40,
        titleBarTopPadding: !hiddenToolbar && Platform.isMacOS ? 24 : 0,
        useSharedTitleBarEngineLinux: const bool.fromEnvironment(
          'SMOKE_SHARED_LINUX',
        ),
      ),
    ).timeout(const Duration(seconds: 20));
    _open.add(view);
    unawaited(view.onClose.then((_) => _open.remove(view)));
    view.launch('http://127.0.0.1:${widget.port}/?id=$id');
    _log('created $id');
    return view;
  }

  Future<void> _waitForPage(Webview view) async {
    for (var attempt = 0; attempt < 100; attempt++) {
      final title = await view.evaluateJavaScript('document.title');
      if (title.toString().contains('Browser')) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('Native page did not load');
  }

  Future<void> _close(Webview view) async {
    view.close();
    view.close(); // Repeated close must be harmless.
    await view.onClose.timeout(const Duration(seconds: 10));
  }

  Future<void> _stress() async {
    if (_running) return;
    setState(() => _running = true);
    try {
      final first = await _create();
      final survivor = await _create();
      final last = await _create();
      await _waitForPage(first);
      await _waitForPage(survivor);
      await _waitForPage(last);
      await _close(first);
      await _close(last);
      survivor.reload();
      for (var i = 0; i < 20; i++) {
        final next = await _create(hiddenToolbar: i == 0);
        if (i < 10) await _waitForPage(next);
        await _close(next);
        _log('cycle ${i + 1}/20');
      }
      await _waitForPage(survivor);
      await _close(survivor);
      final reopened = await _create();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await _close(reopened);
      _log('PASS lifecycle sequence (inspect native logs for renderer errors)');
    } catch (error, stack) {
      _log('FAIL $error');
      debugPrintStack(stackTrace: stack);
    } finally {
      for (final view in List<Webview>.of(_open)) {
        view.close();
      }
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar:
            AppBar(title: const Text('Native WebView lifecycle smoke test')),
        body: Column(
          children: [
            Wrap(
              spacing: 12,
              children: [
                ElevatedButton(
                  onPressed: _running ? null : () => _create(),
                  child: const Text('Open input test window'),
                ),
                ElevatedButton(
                  onPressed: _running ? null : _stress,
                  child: const Text('Run 20 close/recreate cycles'),
                ),
                ElevatedButton(
                  onPressed: () {
                    for (final view in List<Webview>.of(_open)) {
                      view.close();
                    }
                  },
                  child: const Text('Close all browsers'),
                ),
              ],
            ),
            Expanded(
              child:
                  ListView(children: [for (final line in _lines) Text(line)]),
            ),
          ],
        ),
      );
}
