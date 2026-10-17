import 'dart:convert';
import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/material.dart';

import 'demo_state.dart';

const _mono = TextStyle(fontFamily: 'monospace', fontSize: 12.5);

ThemeData _theme(Brightness brightness) => ThemeData(
      useMaterial3: true,
      colorSchemeSeed: Colors.indigo,
      brightness: brightness,
      visualDensity: VisualDensity.compact,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
    );

class DemoApp extends StatefulWidget {
  const DemoApp({super.key, required this.state});
  final DemoState state;

  @override
  State<DemoApp> createState() => _DemoAppState();
}

class _DemoAppState extends State<DemoApp> {
  @override
  void initState() {
    super.initState();
    widget.state.initialize();
  }

  @override
  void dispose() {
    widget.state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        home: _Home(state: widget.state),
      );
}

class _Home extends StatefulWidget {
  const _Home({required this.state});
  final DemoState state;

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  final _script = TextEditingController(text: 'document.title');
  final _message = TextEditingController(text: 'Hello from Flutter');
  var _options = const DemoWindowOptions();
  var _customUrl = 'https://mixin.one';
  var _activityOpen = false;
  var _activityAll = false;

  DemoState get state => widget.state;
  bool get _canOpen => state.available == true && !state.creating;

  @override
  void dispose() {
    _script.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _newWindow() async {
    if (!_canOpen) return;
    final options = await showDialog<DemoWindowOptions>(
      context: context,
      builder: (context) =>
          _NewWindowDialog(initial: _options, initialUrl: _customUrl),
    );
    if (options == null) return;
    // Reopen the dialog with the same choices next time.
    _options = options;
    if (options.url != null) _customUrl = options.url!;
    await state.open(options);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: state,
        builder: (context, _) => DefaultTabController(
          length: DemoPanel.values.length,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Desktop WebView'),
              actions: [_runtime(), const SizedBox(width: 12)],
            ),
            body: LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth >= 760;
              return Column(children: [
                Expanded(
                  child: wide
                      ? Row(children: [
                          SizedBox(width: 240, child: _windowList()),
                          const VerticalDivider(width: 1),
                          Expanded(child: _inspector()),
                        ])
                      : Column(children: [
                          _windowPicker(),
                          const Divider(height: 1),
                          Expanded(child: _inspector()),
                        ]),
                ),
                const Divider(height: 1),
                _activity(constraints.maxHeight),
              ]);
            }),
          ),
        ),
      );

  Widget _runtime() {
    final (icon, label, color) = switch (state.available) {
      null => (Icons.hourglass_top, 'Checking runtime…', null),
      true => (Icons.check_circle, 'Runtime ready', Colors.green),
      false => (Icons.error, 'Runtime unavailable', Colors.red),
    };
    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _newButton({bool expand = false}) {
    final button = FilledButton.icon(
      onPressed: _canOpen ? _newWindow : null,
      icon: state.creating
          ? const SizedBox.square(
              dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.add),
      label: Text(state.creating ? 'Opening…' : 'New window'),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }

  Widget _statusIcon(DemoWindow window) => window.navigation.isLoading
      ? const SizedBox.square(
          dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
      : Icon(switch (window.options.layout) {
          DemoLayout.titleBar => Icons.web,
          DemoLayout.sidebar => Icons.view_sidebar_outlined,
        });

  Widget _windowList() =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
            padding: const EdgeInsets.all(12), child: _newButton(expand: true)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Text('WINDOWS · ${state.windows.length}',
              style: Theme.of(context).textTheme.labelSmall),
        ),
        Expanded(
          child: ListView(children: [
            for (final window in state.windows)
              ListTile(
                selected: state.selectedId == window.id,
                leading: _statusIcon(window),
                title: Text(window.name),
                subtitle: Text(window.navigation.title ?? window.currentUrl,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => state.select(window),
              ),
          ]),
        ),
      ]);

  Widget _windowPicker() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(children: [
          Expanded(
            child: state.windows.isEmpty
                ? const Text('No windows')
                : DropdownButton<int>(
                    isExpanded: true,
                    value: state.selectedId,
                    items: [
                      for (final window in state.windows)
                        DropdownMenuItem(
                          value: window.id,
                          child: Text(
                              '${window.name} · ${window.navigation.title ?? window.currentUrl}',
                              overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (id) => state.select(
                        state.windows.firstWhere((window) => window.id == id)),
                  ),
          ),
          const SizedBox(width: 12),
          _newButton(),
        ]),
      );

  Widget _inspector() {
    final window = state.selected;
    final theme = Theme.of(context);
    if (window == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.web_asset, size: 56, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text('No browser windows', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
              'Open the built-in demo page to try navigation,\nmessages, JavaScript and cookies.',
              textAlign: TextAlign.center),
          const SizedBox(height: 20),
          _newButton(),
        ]),
      );
    }
    final navigation = window.navigation;
    final view = window.webview;
    final busy = window.busy;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
        child: Row(children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  navigation.title?.isNotEmpty == true
                      ? navigation.title!
                      : window.name,
                  style: theme.textTheme.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(
                [
                  window.name,
                  navigation.isLoading ? 'Loading…' : 'Idle',
                  window.options.layout.label,
                  if (window.options.openHidden) 'Hidden',
                ].join(' · '),
                style: theme.textTheme.bodySmall,
              ),
            ]),
          ),
          TextButton.icon(
            onPressed: view.close,
            icon: const Icon(Icons.close),
            label: const Text('Close window'),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
        child: Row(children: [
          IconButton(
            tooltip: 'Back',
            onPressed: navigation.canGoBack && !busy
                ? () =>
                    state.perform(window, DemoPanel.window, 'Back', view.back)
                : null,
            icon: const Icon(Icons.arrow_back),
          ),
          IconButton(
            tooltip: 'Forward',
            onPressed: navigation.canGoForward && !busy
                ? () => state.perform(
                    window, DemoPanel.window, 'Forward', view.forward)
                : null,
            icon: const Icon(Icons.arrow_forward),
          ),
          navigation.isLoading
              ? IconButton(
                  tooltip: 'Stop',
                  onPressed: busy
                      ? null
                      : () => state.perform(
                          window, DemoPanel.window, 'Stop', view.stop),
                  icon: const Icon(Icons.close),
                )
              : IconButton(
                  tooltip: 'Reload',
                  onPressed: busy
                      ? null
                      : () => state.perform(
                          window, DemoPanel.window, 'Reload', view.reload),
                  icon: const Icon(Icons.refresh),
                ),
          const SizedBox(width: 8),
          Expanded(
            child: _AddressBar(
              key: ValueKey(window.id),
              url: window.currentUrl,
              onSubmitted: (url) => state.navigate(window, url),
            ),
          ),
        ]),
      ),
      if (busy)
        const LinearProgressIndicator(minHeight: 2)
      else
        const SizedBox(height: 2),
      const TabBar(tabs: [
        Tab(text: 'Messages'),
        Tab(text: 'JavaScript'),
        Tab(text: 'Cookies'),
        Tab(text: 'Window'),
      ]),
      Expanded(
        child: TabBarView(children: [
          _messages(window),
          _javaScript(window),
          _cookies(window),
          _windowPanel(window),
        ]),
      ),
    ]);
  }

  Widget _panel(DemoWindow window, DemoPanel panel, List<Widget> children) =>
      ListView(padding: const EdgeInsets.all(20), children: [
        ...children,
        if (window.results[panel] case final result?) ...[
          const SizedBox(height: 16),
          _ResultBox(result),
        ],
      ]);

  Widget _hint(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
      );

  /// Disabled while [window] runs another operation.
  Widget _action(DemoWindow window, DemoPanel panel, String label,
      Future<Object?> Function() callback,
      {bool primary = false}) {
    final onPressed = window.busy
        ? null
        : () => state.perform(window, panel, label, callback);
    return primary
        ? FilledButton(onPressed: onPressed, child: Text(label))
        : OutlinedButton(onPressed: onPressed, child: Text(label));
  }

  Widget _messages(DemoWindow window) => _panel(window, DemoPanel.messages, [
        _hint('Messages travel over window.desktopWebview. On the built-in '
            'page, "Send to Flutter" answers back here.'),
        TextField(
          controller: _message,
          decoration: const InputDecoration(labelText: 'Message'),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _action(window, DemoPanel.messages, 'Post message', () async {
            await window.webview.postMessage('demo', {'text': _message.text});
            return null;
          }, primary: true),
          _action(
              window,
              DemoPanel.messages,
              'Call page function',
              () => window.webview.evaluateJavaScript(
                  'window.receiveFromApp(${jsonEncode(_message.text)})')),
        ]),
      ]);

  Widget _javaScript(DemoWindow window) =>
      _panel(window, DemoPanel.javascript, [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final sample in const [
            'document.title',
            'location.href',
            'navigator.userAgent',
            'document.cookie',
          ])
            ActionChip(
              label: Text(sample, style: _mono),
              onPressed: () => setState(() => _script.text = sample),
            ),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _script,
          minLines: 3,
          maxLines: 8,
          style: _mono,
          decoration: const InputDecoration(labelText: 'Expression'),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: _action(window, DemoPanel.javascript, 'Run',
              () => window.webview.evaluateJavaScript(_script.text),
              primary: true),
        ),
      ]);

  Widget _cookies(DemoWindow window) {
    final cookies = window.cookies;
    return _panel(window, DemoPanel.cookies, [
      _hint('Windows share one browser profile. Set a cookie on the built-in '
          'page, then read it here.'),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: window.busy ? null : () => state.readCookies(window),
          icon: const Icon(Icons.cookie_outlined),
          label: const Text('Read cookies'),
        ),
      ),
      if (cookies != null && cookies.isNotEmpty) ...[
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 36,
            dataRowMinHeight: 32,
            dataRowMaxHeight: 40,
            columns: const [
              DataColumn(label: Text('Name')),
              DataColumn(label: Text('Value')),
              DataColumn(label: Text('Domain')),
              DataColumn(label: Text('Path')),
              DataColumn(label: Text('Flags')),
            ],
            rows: [
              for (final cookie in cookies)
                DataRow(cells: [
                  DataCell(SelectableText(cookie.name, style: _mono)),
                  DataCell(SelectableText(cookie.value, style: _mono)),
                  DataCell(Text(cookie.domain)),
                  DataCell(Text(cookie.path)),
                  DataCell(Text([
                    if (cookie.secure) 'Secure',
                    if (cookie.httpOnly) 'HttpOnly',
                    if (cookie.sessionOnly) 'Session',
                  ].join(' '))),
                ]),
            ],
          ),
        ),
      ],
    ]);
  }

  Widget _windowPanel(DemoWindow window) {
    final view = window.webview;
    final theme = Theme.of(context);
    Widget section(String title) => Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Text(title, style: theme.textTheme.titleSmall),
        );
    return _panel(window, DemoPanel.window, [
      if (Platform.isMacOS || Platform.isWindows) ...[
        section('Appearance'),
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.light, label: Text('Light')),
              ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
              ButtonSegment(value: ThemeMode.system, label: Text('System')),
            ],
            selected: {window.appearance},
            onSelectionChanged: window.busy
                ? null
                : (value) => state.perform(window, DemoPanel.window,
                        'Appearance: ${value.single.name}', () async {
                      await view.setBrightness(switch (value.single) {
                        ThemeMode.light => Brightness.light,
                        ThemeMode.dark => Brightness.dark,
                        ThemeMode.system => null,
                      });
                      window.appearance = value.single;
                      return null;
                    }),
          ),
        ),
        const SizedBox(height: 16),
      ],
      section('Native window'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _action(window, DemoPanel.window, 'Native handle',
            () async => '0x${view.nativeWindowHandle.toRadixString(16)}'),
        if (!Platform.isMacOS)
          _action(window, DemoPanel.window, 'Open DevTools', () async {
            await view.openDevToolsWindow();
            return null;
          }),
      ]),
    ]);
  }

  Widget _activity(double height) {
    final theme = Theme.of(context);
    final selected = state.selectedId;
    final events = state.events
        .where((event) =>
            _activityAll || selected == null || event.windowId == selected)
        .toList()
        .reversed
        .toList();
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        InkWell(
          onTap: () => setState(() => _activityOpen = !_activityOpen),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(children: [
              Icon(_activityOpen ? Icons.expand_more : Icons.chevron_right),
              const SizedBox(width: 4),
              Flexible(
                child: Text('Activity · ${events.length}',
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _activityOpen || events.isEmpty
                    ? const SizedBox()
                    : Text(_eventLine(events.first),
                        style: _mono.copyWith(color: theme.colorScheme.outline),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
              ),
              if (_activityOpen) ...[
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, label: Text('This window')),
                    ButtonSegment(value: true, label: Text('All')),
                  ],
                  selected: {_activityAll},
                  onSelectionChanged: (value) =>
                      setState(() => _activityAll = value.single),
                ),
                IconButton(
                  tooltip: 'Clear activity',
                  onPressed: state.clearEvents,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ]),
          ),
        ),
        if (_activityOpen)
          SizedBox(
            height: height < 600 ? 120 : 180,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              children: [
                for (final event in events)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: SelectableText(_eventLine(event), style: _mono),
                  ),
              ],
            ),
          ),
      ]),
    );
  }

  String _eventLine(DemoEvent event) =>
      '${event.time.toIso8601String().substring(11, 19)}  '
      '${event.windowId == null ? 'App' : 'Browser ${event.windowId}'}  '
      '${event.message}';
}

/// Shows the latest operation result; the first line is the operation.
class _ResultBox extends StatelessWidget {
  const _ResultBox(this.result);
  final String result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final split = result.indexOf('\n');
    final title = split < 0 ? result : result.substring(0, split);
    final body = split < 0 ? '' : result.substring(split + 1);
    final failed = title.endsWith('failed');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: failed
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: theme.textTheme.labelLarge),
        if (body.isNotEmpty) ...[
          const SizedBox(height: 6),
          SelectableText(_pretty(body), style: _mono),
        ],
      ]),
    );
  }

  static String _pretty(String text) {
    try {
      final value = jsonDecode(text);
      if (value is Map || value is List) {
        return const JsonEncoder.withIndent('  ').convert(value);
      }
    } on FormatException {
      // Not JSON; show as is.
    }
    return text;
  }
}

/// Follows the page URL until the user starts editing it.
class _AddressBar extends StatefulWidget {
  const _AddressBar({super.key, required this.url, required this.onSubmitted});
  final String url;
  final bool Function(String url) onSubmitted;

  @override
  State<_AddressBar> createState() => _AddressBarState();
}

class _AddressBarState extends State<_AddressBar> {
  late final _controller = TextEditingController(text: widget.url);
  final _focus = FocusNode();

  @override
  void didUpdateWidget(_AddressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && widget.url != _controller.text) {
      _controller.text = widget.url;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _controller,
        focusNode: _focus,
        style: _mono,
        decoration: const InputDecoration(
          hintText: 'Enter a URL',
          prefixIcon: Icon(Icons.public, size: 18),
        ),
        onSubmitted: (value) {
          if (widget.onSubmitted(value)) _focus.unfocus();
        },
      );
}

class _NewWindowDialog extends StatefulWidget {
  const _NewWindowDialog({required this.initial, required this.initialUrl});
  final DemoWindowOptions initial;
  final String initialUrl;

  @override
  State<_NewWindowDialog> createState() => _NewWindowDialogState();
}

class _NewWindowDialogState extends State<_NewWindowDialog> {
  List<(String, bool, TitleBarOptions Function(bool))> get _titleBarItems {
    final t = _titleBar;
    TitleBarOptions copy(
            {bool? navigation, bool? reload, bool? title, bool? host}) =>
        TitleBarOptions(
          showNavigation: navigation ?? t.showNavigation,
          showReload: reload ?? t.showReload,
          showTitle: title ?? t.showTitle,
          showHost: host ?? t.showHost,
        );
    return [
      ('Navigation', t.showNavigation, (v) => copy(navigation: v)),
      ('Reload', t.showReload, (v) => copy(reload: v)),
      ('Title', t.showTitle, (v) => copy(title: v)),
      ('Host', t.showHost, (v) => copy(host: v)),
    ];
  }

  late var _custom = widget.initial.url != null;
  late final _url = TextEditingController(text: widget.initialUrl);
  late var _layout = widget.initial.layout;
  late var _titleBar = widget.initial.titleBar;
  late var _hidden = widget.initial.openHidden;
  late var _denyMedia = widget.initial.denyMedia;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  void _submit() {
    if (_custom && DemoState.normalizeUrl(_url.text) == null) {
      setState(() => _error = 'Enter an http:// or https:// URL');
      return;
    }
    Navigator.of(context).pop(DemoWindowOptions(
      url: _custom ? _url.text.trim() : null,
      layout: _layout,
      titleBar: _titleBar,
      openHidden: _hidden,
      denyMedia: _denyMedia,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(text, style: theme.textTheme.titleSmall),
        );
    return AlertDialog(
      title: const Text('New browser window'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              label('Page'),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                      value: false,
                      icon: Icon(Icons.science_outlined),
                      label: Text('Built-in demo')),
                  ButtonSegment(
                      value: true, icon: Icon(Icons.link), label: Text('URL')),
                ],
                selected: {_custom},
                onSelectionChanged: (value) =>
                    setState(() => _custom = value.single),
              ),
              if (_custom) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _url,
                  autofocus: true,
                  decoration:
                      InputDecoration(labelText: 'URL', errorText: _error),
                  onChanged: (_) => setState(() => _error = null),
                  onSubmitted: (_) => _submit(),
                ),
              ],
              label('Layout'),
              SegmentedButton<DemoLayout>(
                showSelectedIcon: false,
                segments: [
                  for (final layout in DemoLayout.values)
                    ButtonSegment(value: layout, label: Text(layout.label)),
                ],
                selected: {_layout},
                onSelectionChanged: (value) =>
                    setState(() => _layout = value.single),
              ),
              const SizedBox(height: 6),
              Text(
                switch (_layout) {
                  DemoLayout.titleBar =>
                    'The default composer puts navigation, the page title and host into the native title bar.',
                  DemoLayout.sidebar =>
                    'The example runner\'s own native composer puts controls left of the page.',
                },
                style: theme.textTheme.bodySmall,
              ),
              if (_layout == DemoLayout.titleBar) ...[
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final (name, shown, toggle) in _titleBarItems)
                    FilterChip(
                      label: Text(name),
                      selected: shown,
                      onSelected: (value) =>
                          setState(() => _titleBar = toggle(value)),
                    ),
                ]),
              ],
              if (Platform.isWindows)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Windows options'),
                  children: [
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Open hidden'),
                      value: _hidden,
                      onChanged: (value) => setState(() => _hidden = value!),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Deny camera and microphone'),
                      value: _denyMedia,
                      onChanged: (value) => setState(() => _denyMedia = value!),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Open')),
      ],
    );
  }
}
