import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'demo_state.dart';

class DemoApp extends StatefulWidget {
  const DemoApp({super.key, required this.state});
  final DemoState state;

  @override
  State<DemoApp> createState() => _DemoAppState();
}

class _DemoAppState extends State<DemoApp> {
  final _url = TextEditingController(text: 'https://example.com');
  final _script = TextEditingController(text: 'document.title');
  final _message = TextEditingController(text: 'Hello from Flutter');
  bool _builtIn = true;
  bool _titleBar = true;
  bool _hidden = false;
  bool _denyMedia = false;
  int? _eventWindow;

  DemoState get state => widget.state;

  @override
  void initState() {
    super.initState();
    state.initialize();
  }

  @override
  void dispose() {
    _url.dispose();
    _script.dispose();
    _message.dispose();
    state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: state.darkMode,
        builder: (context, dark, _) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: state.theme,
          home: AnimatedBuilder(
            animation: state,
            builder: (context, _) => Scaffold(
              appBar: AppBar(
                title: const Text('Desktop WebView'),
                actions: [
                  IconButton(
                    tooltip: 'Toggle app theme',
                    onPressed: () => state.darkMode.value = !dark,
                    icon: Icon(dark ? Icons.light_mode : Icons.dark_mode),
                  ),
                ],
              ),
              body: LayoutBuilder(builder: (context, constraints) {
                return Column(children: [
                  _launcher(),
                  const Divider(height: 1),
                  Expanded(
                    child: constraints.maxWidth >= 760
                        ? Row(children: [
                            SizedBox(width: 220, child: _windows()),
                            const VerticalDivider(width: 1),
                            Expanded(child: _details(context)),
                          ])
                        : Column(children: [
                            SizedBox(height: 108, child: _windows()),
                            const Divider(height: 1),
                            Expanded(child: _details(context)),
                          ]),
                  ),
                  const Divider(height: 1),
                  SizedBox(
                    height: constraints.maxHeight < 600 ? 130 : 190,
                    child: _events(),
                  ),
                ]);
              }),
            ),
          ),
        ),
      );

  Widget _launcher() => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(children: [
            DropdownButton<bool>(
              value: _builtIn,
              items: const [
                DropdownMenuItem(value: true, child: Text('Built-in demo')),
                DropdownMenuItem(value: false, child: Text('Custom URL')),
              ],
              onChanged: (value) => setState(() => _builtIn = value!),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _builtIn
                  ? Text(state.pages.url(1).replaceAll('?id=1', ''),
                      overflow: TextOverflow.ellipsis)
                  : TextField(
                      controller: _url,
                      decoration: const InputDecoration(labelText: 'URL'),
                      onSubmitted: (_) => _open(1),
                    ),
            ),
          ]),
          Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _check('Flutter titlebar', _titleBar,
                    (value) => _titleBar = value),
                if (Platform.isWindows) ...[
                  _check('Open hidden', _hidden, (value) => _hidden = value),
                  _check('Deny camera / mic', _denyMedia,
                      (value) => _denyMedia = value),
                ],
                FilledButton.icon(
                  onPressed: state.available == true && !state.creating
                      ? () => _open(1)
                      : null,
                  icon: const Icon(Icons.add),
                  label: Text(state.creating ? 'Opening…' : 'Open window'),
                ),
                OutlinedButton(
                  onPressed: state.available == true && !state.creating
                      ? () => _open(3)
                      : null,
                  child: const Text('Open 3'),
                ),
                if (state.available != true)
                  Text(state.available == null
                      ? 'Checking runtime…'
                      : 'Browser runtime unavailable'),
              ]),
        ]),
      );

  Widget _check(String label, bool value, ValueChanged<bool> change) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
              value: value,
              onChanged: (value) => setState(() => change(value!))),
          Text(label),
        ],
      );

  void _open(int count) {
    if (state.available != true || state.creating) return;
    state.open(
      url: _builtIn ? null : _url.text.trim(),
      count: count,
      showTitleBar: _titleBar,
      openHidden: _hidden,
      denyMedia: _denyMedia,
    );
  }

  Widget _windows() =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Text('WINDOWS · ${state.windows.length}'),
        ),
        Expanded(
          child: state.windows.isEmpty
              ? const Center(child: Text('Open a window to begin.'))
              : ListView(children: [
                  for (final window in state.windows)
                    ListTile(
                      dense: true,
                      selected: state.selectedId == window.id,
                      leading: Icon(window.webview.isNavigating.value
                          ? Icons.hourglass_top
                          : Icons.web),
                      title: Text('Browser ${window.id}'),
                      subtitle: Text(window.url,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => state.select(window),
                    ),
                ]),
        ),
      ]);

  Widget _details(BuildContext context) {
    final window = state.selected;
    if (window == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
              'Explore native browser windows\n\nOpen the built-in demo, send a message from the page,\nand inspect messages, cookies and navigation.',
              textAlign: TextAlign.center),
        ),
      );
    }
    final view = window.webview;
    Widget action(String label, Future<Object?> Function() callback,
            {bool enabled = true}) =>
        OutlinedButton(
          onPressed: !window.busy && enabled
              ? () => state.perform(window, label, callback)
              : null,
          child: Text(label),
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Browser ${window.id}',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        SelectableText(window.url),
        const SizedBox(height: 8),
        Text(view.isNavigating.value ? 'Loading…' : 'Idle'),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          action('Back', view.back, enabled: window.canGoBack),
          action('Forward', view.forward, enabled: window.canGoForward),
          action('Reload', view.reload),
          action('Stop', view.stop, enabled: view.isNavigating.value),
          TextButton.icon(
              onPressed: view.close,
              icon: const Icon(Icons.close),
              label: const Text('Close window')),
        ]),
        const Divider(height: 32),
        Text('JavaScript', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        TextField(
            controller: _script,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Expression')),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          action('Execute', () => view.evaluateJavaScript(_script.text)),
          action('Read cookies', () async {
            final cookies = await view.getAllCookies();
            return const JsonEncoder.withIndent('  ')
                .convert(cookies.map((cookie) => cookie.toJson()).toList());
          }),
        ]),
        const SizedBox(height: 16),
        TextField(
            controller: _message,
            decoration:
                const InputDecoration(labelText: 'Message to built-in page')),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          action(
              'Send to page',
              () => view.evaluateJavaScript(
                  'window.receiveFromApp(${jsonEncode(_message.text)})')),
          if (Platform.isWindows)
            action('Post web message',
                () => view.postWebMessageAsString(_message.text)),
        ]),
        const SizedBox(height: 12),
        if (window.busy) const LinearProgressIndicator(),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SelectableText(window.result,
                style: const TextStyle(fontFamily: 'monospace')),
          ),
        ),
        if (Platform.isWindows) ...[
          const Divider(height: 32),
          Text('Window options · ${Platform.operatingSystem}',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (Platform.isWindows) ...[
              action('Show', () => view.setWebviewWindowVisibility(true)),
              action('Hide', () => view.setWebviewWindowVisibility(false)),
              action('Activate', () => view.bringToForeground()),
              action('Move / resize',
                  () => view.moveWebviewWindow(100, 100, 960, 720)),
              action('Position', view.getPositionalParameters),
              action('DevTools', view.openDevToolsWindow),
            ],
          ]),
        ],
      ]),
    );
  }

  Widget _events() {
    final ids = state.events
        .map((event) => event.windowId)
        .whereType<int>()
        .toSet()
        .toList()
      ..sort();
    final filter = ids.contains(_eventWindow) ? _eventWindow : null;
    final events = state.events
        .where((event) => filter == null || event.windowId == filter)
        .toList()
        .reversed;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(children: [
        Row(children: [
          const Expanded(child: Text('EVENT LOG · latest 200')),
          DropdownButton<int>(
            value: filter,
            hint: const Text('All windows'),
            items: [
              const DropdownMenuItem<int>(
                  value: null, child: Text('All windows')),
              for (final id in ids)
                DropdownMenuItem(value: id, child: Text('Browser $id')),
            ],
            onChanged: (value) => setState(() => _eventWindow = value),
          ),
          IconButton(
              tooltip: 'Clear log',
              onPressed: state.clearEvents,
              icon: const Icon(Icons.delete_outline)),
        ]),
        Expanded(
          child: ListView(children: [
            for (final event in events)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: SelectableText(
                  '${event.time.toIso8601String().substring(11, 19)}  ${event.windowId == null ? 'App' : 'Browser ${event.windowId}'}  ${event.message}',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}
