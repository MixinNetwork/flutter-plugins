import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const MyApp());

const _ink = Color(0xFF18233B);
const _muted = Color(0xFF647089);
const _accent = Color(0xFF355BD8);
const _border = Color(0xFFE0E5EF);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Desktop Drop',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: _accent),
      scaffoldBackgroundColor: const Color(0xFFF5F7FB),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: _ink,
        ),
        titleMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: _ink,
        ),
        bodyMedium: TextStyle(fontSize: 13, height: 1.5, color: _muted),
      ),
    ),
    home: const DropPlayground(),
  );
}

class DropPlayground extends StatefulWidget {
  const DropPlayground({super.key});

  @override
  State<DropPlayground> createState() => _DropPlaygroundState();
}

class _DropPlaygroundState extends State<DropPlayground> {
  final _enabled = <String, bool>{};
  String? _hovering;
  DropEventDetails? _preview;
  DropDoneDetails? _lastDrop;
  String? _lastTarget;
  DateTime? _lastTime;
  int _dropCount = 0;
  (String, Uint8List)? _bookmark;
  bool _reading = false;

  bool get _macOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
  bool _isEnabled(String target) => _enabled[target] ?? true;

  bool _acceptsFiles(DropOffer offer, String? suffix) {
    if (!offer.types.contains(DropType.file)) return false;
    if (suffix == null) return true;
    if (offer.files.isEmpty) return !offer.isComplete;
    return offer.files.every(
      (file) => file.name.isEmpty
          ? !offer.isComplete && !file.isPromised
          : file.name.toLowerCase().endsWith(suffix),
    );
  }

  @override
  void initState() {
    super.initState();
    _restoreBookmark();
  }

  Future<void> _restoreBookmark() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString('apple-bookmark');
    if (saved == null) return;
    try {
      final value = jsonDecode(saved) as Map<String, dynamic>;
      final bookmark = (
        value['path'] as String,
        base64Decode(value['apple-bookmark'] as String),
      );
      if (mounted) setState(() => _bookmark = bookmark);
    } catch (_) {
      // An obsolete example preference should not prevent the playground opening.
    }
  }

  void _hover(String target, DropEventDetails details) {
    setState(() {
      _hovering = target;
      _preview = details;
    });
  }

  void _exit(String target) {
    if (_hovering != target) return;
    setState(() {
      _hovering = null;
      _preview = null;
    });
  }

  void _received(String target, DropDoneDetails details) {
    setState(() {
      _lastDrop = details;
      _lastTarget = target;
      _lastTime = DateTime.now();
      _dropCount++;
    });
    debugPrint(
      'Drop #$_dropCount -> $target: ${details.files.length} files, '
      'text=${details.text != null}, urls=${details.urls.length}, '
      'position=${details.globalPosition}',
    );
  }

  Widget _destination(
    String target,
    bool Function(DropOffer) accepts,
    Widget child,
  ) => DropTarget(
    key: ValueKey('target-$target'),
    enable: _isEnabled(target),
    onWillAccept: (details) => _isEnabled(target) && accepts(details.offer),
    onDragEntered: (details) => _hover(target, details),
    onDragUpdated: (details) => _hover(target, details),
    onDragExited: (_) => _exit(target),
    onDragDone: (details) => _received(target, details),
    child: child,
  );

  Widget _toggle(String target) => Tooltip(
    message: 'Toggle acceptance for $target',
    child: Switch(
      key: ValueKey('toggle-$target'),
      value: _isEnabled(target),
      onChanged: (value) => setState(() => _enabled[target] = value),
    ),
  );

  Widget _frame(String target, Widget child) {
    final active = _hovering == target;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      height:
          188 *
          (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(
            1,
            double.infinity,
          ),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFEDF2FF) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active ? _accent : _border,
          width: active ? 2 : 1,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: child,
    );
  }

  Widget _targetCard(
    String target,
    IconData icon,
    DropType type,
    String rule, {
    String? suffix,
  }) {
    final active = _hovering == target;
    final enabled = _isEnabled(target);
    return _destination(
      target,
      (offer) => type == DropType.file
          ? _acceptsFiles(offer, suffix)
          : offer.types.contains(type),
      _frame(
        target,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: enabled ? _accent : _muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    target,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _toggle(target),
              ],
            ),
            const Spacer(),
            Text(
              active
                  ? 'Ready to drop'
                  : enabled
                  ? 'Drop here'
                  : 'Acceptance off',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: active
                    ? _accent
                    : enabled
                    ? _ink
                    : _muted,
              ),
            ),
            const SizedBox(height: 5),
            Text(rule, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _nestedCard() {
    const parent = 'Parent';
    const child = 'Child TXT';
    final active = _hovering == child;
    return _destination(
      parent,
      (offer) => offer.types.isNotEmpty,
      _frame(
        parent,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.layers_outlined, color: _accent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Parent · any type',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _toggle(parent),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: _destination(
                child,
                (offer) => _acceptsFiles(offer, '.txt'),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: active
                        ? const Color(0xFFDCE6FF)
                        : const Color(0xFFF5F7FB),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: active ? _accent : _border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              active ? 'Child ready' : 'Child · TXT',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: _ink,
                              ),
                            ),
                            const Text(
                              'Otherwise → parent',
                              style: TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      _toggle(child),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _targets() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionTitle(
        'Drop targets',
        'Each switch changes acceptance immediately.',
      ),
      const SizedBox(height: 14),
      LayoutBuilder(
        builder: (context, constraints) {
          final columns =
              constraints.maxWidth >=
                  560 * (MediaQuery.textScalerOf(context).scale(14) / 14)
              ? 2
              : 1;
          final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _targetCard(
                'All files',
                Icons.folder_open_outlined,
                DropType.file,
                'Files and folders',
              ),
              _targetCard(
                'TXT files',
                Icons.description_outlined,
                DropType.file,
                'Every filename must end in .txt',
                suffix: '.txt',
              ),
              _targetCard(
                'PNG files',
                Icons.image_outlined,
                DropType.file,
                'Every filename must end in .png',
                suffix: '.png',
              ),
              _targetCard(
                'Text',
                Icons.notes_outlined,
                DropType.text,
                'Plain text from another app',
              ),
              _targetCard(
                'URLs',
                Icons.link_outlined,
                DropType.url,
                'Links advertised by the source',
              ),
              _nestedCard(),
            ].map((child) => SizedBox(width: width, child: child)).toList(),
          );
        },
      ),
      const SizedBox(height: 14),
      const Text(
        'Try the nested area with a TXT file, then a PNG or a link. '
        'Only the first accepting target receives the drop.',
      ),
    ],
  );

  Widget _sectionTitle(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(subtitle),
    ],
  );

  Widget _panel(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: _border),
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );

  String _point(Offset point) =>
      '${point.dx.toStringAsFixed(1)}, ${point.dy.toStringAsFixed(1)}';
  Widget _label(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: _muted,
          ),
        ),
        const SizedBox(height: 3),
        SelectableText(
          value,
          style: const TextStyle(fontSize: 13, color: _ink, height: 1.4),
        ),
      ],
    ),
  );

  Widget _details() {
    final drop = _lastDrop;
    final preview = _preview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          'Drop inspector',
          'Accepted content stays here after the drop.',
        ),
        const SizedBox(height: 14),
        if (preview != null) ...[
          _panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('HOVERING OVER', _hovering!),
                _label(
                  'ADVERTISED TYPES',
                  preview.offer.types.map((type) => type.name).join(' · '),
                ),
                _label('LOCAL POSITION', _point(preview.localPosition)),
                Text(
                  preview.offer.isComplete
                      ? 'Preview data available'
                      : 'Some values are available only after drop.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        _panel(
          drop == null
              ? const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.move_to_inbox_outlined, size: 30, color: _muted),
                    SizedBox(height: 16),
                    Text(
                      'No drops yet',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: _ink,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Drag from Finder, Explorer, a browser, or another app. '
                      'Release inside a matching target to inspect its content.',
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Drop #$_dropCount',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Clear last drop',
                          onPressed: () => setState(() {
                            _lastDrop = null;
                            _lastTarget = null;
                            _lastTime = null;
                          }),
                          icon: const Icon(Icons.clear, size: 18),
                        ),
                      ],
                    ),
                    _label('RECEIVED BY', _lastTarget!),
                    _label(
                      'TIME',
                      _lastTime!
                          .toIso8601String()
                          .split('T')
                          .last
                          .split('.')
                          .first,
                    ),
                    _label(
                      'POSITION',
                      'Global (${_point(drop.globalPosition)})\nLocal (${_point(drop.localPosition)})',
                    ),
                    if (drop.text != null) _label('TEXT', drop.text!),
                    if (drop.urls.isNotEmpty)
                      _label('URLS', drop.urls.join('\n')),
                    if (drop.rawText != null)
                      _label('LINUX TRANSFER', drop.rawText!),
                    if (drop.files.isNotEmpty) ...[
                      Text(
                        '${drop.files.length} ${drop.files.length == 1 ? 'file' : 'files'}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: (drop.files.length * 114.0).clamp(100, 300),
                        child: ListView.separated(
                          itemCount: drop.files.length,
                          separatorBuilder: (_, index) =>
                              const Divider(height: 16),
                          itemBuilder: (context, index) =>
                              _fileRow(drop.files[index]),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
        if (_macOS) ...[const SizedBox(height: 12), _bookmarkPanel()],
        const SizedBox(height: 12),
        const Text(
          'Hover data can be incomplete. Acceptance is checked again when '
          'you release. Off targets and rejected content receive no drop.',
        ),
      ],
    );
  }

  Widget _fileRow(DropItem file) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        file.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600, color: _ink),
      ),
      const SizedBox(height: 4),
      SelectableText(
        file.path,
        maxLines: 2,
        style: const TextStyle(fontSize: 11, color: _muted),
      ),
      if (file is DropItemDirectory)
        Text('Folder · ${file.children.length} browser entries'),
      if (file.fromPromise) const Text('Delivered as a macOS file promise'),
      Wrap(
        spacing: 4,
        children: [
          if (file is! DropItemDirectory)
            TextButton.icon(
              onPressed: _reading
                  ? null
                  : () => _readFile(file, bookmark: file.extraAppleBookmark),
              icon: const Icon(Icons.visibility_outlined, size: 15),
              label: const Text('Read file'),
            ),
          if (_macOS && file.extraAppleBookmark != null)
            TextButton.icon(
              onPressed: () => _saveBookmark(file),
              icon: const Icon(Icons.bookmark_add_outlined, size: 15),
              label: const Text('Save bookmark'),
            ),
        ],
      ),
    ],
  );

  Widget _bookmarkPanel() => _panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'macOS file access',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          _bookmark == null
              ? 'Drop a file and save its bookmark. Restart the app to test access.'
              : 'Saved: ${_bookmark!.$1.split('/').last}',
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(
              onPressed: _bookmark == null || _reading
                  ? null
                  : () => _readFile(
                      XFile(_bookmark!.$1),
                      bookmark: _bookmark!.$2,
                    ),
              child: const Text('Read with access'),
            ),
            TextButton(
              onPressed: _bookmark == null || _reading
                  ? null
                  : () => _readFile(XFile(_bookmark!.$1)),
              child: const Text('Read without access'),
            ),
          ],
        ),
      ],
    ),
  );

  Future<void> _saveBookmark(DropItem file) async {
    final bytes = file.extraAppleBookmark;
    if (bytes == null) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'apple-bookmark',
      jsonEncode({'path': file.path, 'apple-bookmark': base64Encode(bytes)}),
    );
    if (!mounted) return;
    setState(() => _bookmark = (file.path, bytes));
    _message('Bookmark saved. Restart the app to test persistent access.');
  }

  Future<void> _readFile(XFile file, {Uint8List? bookmark}) async {
    setState(() => _reading = true);
    var accessed = false;
    try {
      if (bookmark != null) {
        accessed = await DesktopDrop.instance
            .startAccessingSecurityScopedResource(bookmark: bookmark);
        if (!accessed) {
          throw StateError('Security-scoped access was not granted');
        }
      }
      final size = await file.length();
      final read = await file
          .openRead(0, size.clamp(0, 64))
          .fold<int>(0, (total, bytes) => total + bytes.length);
      _message('${file.name}: $size bytes. Read $read bytes successfully.');
    } catch (error) {
      _message('Cannot read ${file.name}: $error');
    } finally {
      if (accessed) {
        await DesktopDrop.instance.stopAccessingSecurityScopedResource(
          bookmark: bookmark!,
        );
      }
      if (mounted) setState(() => _reading = false);
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Desktop Drop',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Files, text, and links. Different targets, different rules.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: _hovering == null
                            ? const Color(0xFFE8EDF6)
                            : const Color(0xFFDFE8FF),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _hovering == null ? 'Ready' : 'Accepting',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _accent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth >= 730) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: SingleChildScrollView(child: _targets()),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              flex: 2,
                              child: SingleChildScrollView(child: _details()),
                            ),
                          ],
                        );
                      }
                      return ListView(
                        children: [
                          _targets(),
                          const SizedBox(height: 28),
                          _details(),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
