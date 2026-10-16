import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common/app_theme.dart';
import '../common/bookmark_tools.dart';
import '../common/received_item.dart';

String _name(DropItem item) => switch (item) {
  DropFileItem(:final name) ||
  DropDirectoryItem(:final name) => name.isEmpty ? 'Unnamed item' : name,
  DropStringItem(:final mimeType) => switch (mimeType) {
    'text/plain' => 'Text',
    'text/html' => 'HTML',
    'text/uri-list' => 'Links',
    _ => mimeType,
  },
};
String _kind(DropItem item) => switch (item) {
  DropFileItem() => 'File',
  DropDirectoryItem() => 'Directory',
  DropStringItem() => 'String',
};
IconData _icon(DropItem item) => switch (item) {
  DropFileItem() => Icons.insert_drive_file_outlined,
  DropDirectoryItem() => Icons.folder_outlined,
  DropStringItem(:final mimeType) =>
    mimeType == 'text/uri-list'
        ? Icons.link
        : mimeType == 'text/html'
        ? Icons.code
        : Icons.notes_outlined,
};

class DropContent extends StatefulWidget {
  const DropContent({
    super.key,
    required this.event,
    required this.receiver,
    required this.onClear,
    this.content = const {},
  });
  final DropDetails? event;
  final Map<DropItem, ReceivedItem> content;
  final String? receiver;
  final VoidCallback onClear;

  @override
  State<DropContent> createState() => _DropContentState();
}

class _DropContentState extends State<DropContent> {
  int _selected = 0;
  final _navigation = <DropItem>[];

  DropItem? get _root => widget.event == null || widget.event!.items.isEmpty
      ? null
      : widget.event!.items[_selected];
  DropItem? get _item => _navigation.isEmpty ? _root : _navigation.last;

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final item = _item;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 36,
          child: Row(
            children: [
              const Text(
                'Received',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.ink,
                ),
              ),
              if (event != null)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      '· ${event.items.length} representations',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.muted,
                      ),
                    ),
                  ),
                )
              else
                const Spacer(),
              if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS)
                IconButton(
                  tooltip: 'Saved bookmark',
                  iconSize: 18,
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const AlertDialog(
                      title: Text('Saved bookmark'),
                      content: SizedBox(width: 420, child: BookmarkTools()),
                    ),
                  ),
                  icon: const Icon(Icons.bookmark_outline),
                ),
              TextButton(
                onPressed: event == null ? null : widget.onClear,
                child: const Text('Clear'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border),
            ),
            child: event == null || item == null
                ? const _Message(
                    icon: Icons.move_to_inbox_outlined,
                    title: 'Nothing dropped yet',
                    description: 'Drop on a target to see its files, folders and string representations here.',
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 142,
                        child: ColoredBox(
                          color: const Color(0xFFFAFBFD),
                          child: ListView.builder(
                            key: const ValueKey('received-items'),
                            padding: const EdgeInsets.all(6),
                            itemCount: event.items.length,
                            itemBuilder: (context, index) {
                              final entry = event.items[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Material(
                                  color: index == _selected
                                      ? AppTheme.accentLight
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  child: InkWell(
                                    key: ValueKey('item-$index'),
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: () => setState(() {
                                      _selected = index;
                                      _navigation.clear();
                                    }),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 9,
                                        vertical: 12,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                            _icon(entry),
                                            size: 18,
                                            color: index == _selected
                                                ? AppTheme.accent
                                                : AppTheme.muted,
                                          ),
                                          const SizedBox(height: 7),
                                          Text(
                                            _name(entry),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: index == _selected
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
                                              color: AppTheme.ink,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            _kind(entry),
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: AppTheme.muted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(14, 12, 6, 10),
                              child: Row(
                                children: [
                                  if (_navigation.isNotEmpty)
                                    IconButton(
                                      tooltip: 'Back to folder',
                                      onPressed: () => setState(
                                        () => _navigation.removeLast(),
                                      ),
                                      icon: const Icon(
                                        Icons.arrow_back,
                                        size: 18,
                                      ),
                                    ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _name(item),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.ink,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          'Received by ${widget.receiver} · ${event.operation.name}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1),
                            Expanded(
                              child: _ItemContent(
                                key: ObjectKey(item),
                                item: item,
                                event: event,
                                received: widget.content[item],
                                onOpen: (child) =>
                                    setState(() => _navigation.add(child)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _ItemContent extends StatefulWidget {
  const _ItemContent({
    super.key,
    required this.item,
    required this.event,
    required this.received,
    required this.onOpen,
  });
  final DropItem item;
  final DropDetails event;
  final ReceivedItem? received;
  final ValueChanged<DropItem> onOpen;

  @override
  State<_ItemContent> createState() => _ItemContentState();
}

class _ItemContentState extends State<_ItemContent> {
  bool _busy = false;
  String? _error;
  bool _expired = false;
  Uint8List? _image;
  String? _text;
  String? _hex;
  String? _imageInfo;
  String? _notice;
  List<DropItem>? _children;
  bool _actualSize = false;
  bool _details = false;
  int _request = 0;

  bool get _isImage {
    final item = widget.item;
    return item is DropFileItem &&
        ((item.mimeType?.startsWith('image/') ?? false) ||
            RegExp(
              r'\.(png|jpe?g|gif|webp|bmp|tiff?|heic|avif)$',
              caseSensitive: false,
            ).hasMatch(item.name));
  }

  bool get _isText {
    final item = widget.item;
    return item is DropFileItem &&
        ((item.mimeType?.startsWith('text/') ?? false) ||
            RegExp(
              r'\.(txt|md|json|csv|log|html?|xml|ya?ml|dart|js|css|swift|kt|cc|cpp|h)$',
              caseSensitive: false,
            ).hasMatch(item.name));
  }

  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  @override
  void didUpdateWidget(_ItemContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.received != widget.received) unawaited(_prepare());
  }

  Future<void> _prepare() async {
    final request = ++_request;
    final received = widget.received;
    _busy = received == null;
    _error = received?.error?.toString();
    _expired =
        received?.error is PlatformException &&
        (received!.error as PlatformException).code == 'source_expired';
    _image = null;
    _text = null;
    _hex = null;
    _imageInfo = null;
    _notice = null;
    _children = received?.children;
    final bytes = received?.bytes;
    if (bytes == null) return;
    if (_isImage) {
      try {
        final codec = await ui.instantiateImageCodec(bytes);
        try {
          final frame = await codec.getNextFrame();
          try {
            if (!mounted || request != _request) return;
            _imageInfo =
                '${frame.image.width} × ${frame.image.height} · ${AppTheme.formatBytes(bytes.length)}';
            _image = bytes;
          } finally {
            frame.image.dispose();
          }
        } finally {
          codec.dispose();
        }
      } catch (_) {
        if (!mounted || request != _request) return;
        _notice =
            'Content received, but Flutter cannot preview this image format.';
        _hex = _hexDump(
          Uint8List.sublistView(bytes, 0, bytes.length.clamp(0, 256)),
        );
      }
      if (mounted && request == _request) setState(() {});
    } else if (_isText) {
      final limit = bytes.length.clamp(0, 64 * 1024);
      _text = utf8.decode(
        Uint8List.sublistView(bytes, 0, limit),
        allowMalformed: true,
      );
      if (limit < bytes.length) {
        _notice =
            'Received ${AppTheme.formatBytes(bytes.length)}. Showing the first ${AppTheme.formatBytes(limit)}.';
      }
    } else {
      _hex = _hexDump(
        Uint8List.sublistView(bytes, 0, bytes.length.clamp(0, 256)),
      );
      _notice =
          'Received ${AppTheme.formatBytes(bytes.length)}. Showing up to 256 bytes.';
    }
  }

  String _hexDump(Uint8List bytes) {
    final lines = <String>[];
    for (var offset = 0; offset < bytes.length; offset += 16) {
      final end = (offset + 16).clamp(0, bytes.length);
      final row = bytes.sublist(offset, end);
      final hex = row
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join(' ')
          .padRight(47);
      final ascii = String.fromCharCodes(
        row.map((byte) => byte >= 32 && byte <= 126 ? byte : 46),
      );
      lines.add('${offset.toRadixString(16).padLeft(8, '0')}  $hex  $ascii');
    }
    return lines.isEmpty ? 'Empty file' : lines.join('\n');
  }

  Widget _actions() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (widget.item case DropStringItem(:final value))
          TextButton.icon(
            onPressed: () => Clipboard.setData(ClipboardData(text: value)),
            icon: const Icon(Icons.copy_outlined, size: 15),
            label: const Text('Copy'),
          ),
        if (_image != null)
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Fit')),
              ButtonSegment(value: true, label: Text('100%')),
            ],
            selected: {_actualSize},
            onSelectionChanged: (values) =>
                setState(() => _actualSize = values.single),
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
          ),
      ],
    ),
  );

  Widget _body() {
    if (_busy) {
      return const _Message(
        icon: Icons.hourglass_empty,
        title: 'Reading from source…',
        busy: true,
      );
    }
    if (_error != null) {
      return _Message(
        icon: Icons.error_outline,
        title: _expired
            ? 'Source is no longer available'
            : 'Could not read this item',
        description: _expired
            ? 'Drop it again to obtain a new reference.\n$_error'
            : _error,
      );
    }
    if (_image case final Uint8List bytes) {
      final image = Image.memory(
        bytes,
        fit: BoxFit.scaleDown,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, error, _) => _Message(
          icon: Icons.broken_image_outlined,
          title: 'Preview unavailable',
          description: error.toString(),
        ),
      );
      return ClipRect(
        child: CustomPaint(
          painter: const _Checkerboard(),
          child: LayoutBuilder(
            builder: (context, constraints) => _actualSize
                ? InteractiveViewer(
                    constrained: false,
                    minScale: .1,
                    maxScale: 8,
                    child: image,
                  )
                : SizedBox(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: image,
                    ),
                  ),
          ),
        ),
      );
    }
    if (_text != null) return _textView(_text!);
    if (_hex != null) return _textView(_hex!, code: true);
    if (_children case final List<DropItem> children) {
      if (children.isEmpty) {
        return const _Message(
          icon: Icons.folder_open_outlined,
          title: 'Empty folder',
        );
      }
      return ListView.builder(
        itemCount: children.length,
        itemBuilder: (context, index) {
          final item = children[index];
          return ListTile(
            dense: true,
            leading: Icon(_icon(item), size: 19),
            title: Text(
              _name(item),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () => widget.onOpen(item),
          );
        },
      );
    }
    if (widget.item case DropStringItem(:final mimeType, :final value)) {
      if (mimeType == 'text/uri-list') {
        return ListView(
          children: [
            for (final line in const LineSplitter().convert(value))
              if (line.isNotEmpty)
                ListTile(
                  dense: true,
                  title: SelectableText(
                    line,
                    style: TextStyle(
                      fontSize: 12,
                      color: line.startsWith('#')
                          ? AppTheme.muted
                          : AppTheme.accent,
                    ),
                  ),
                  trailing: line.startsWith('#')
                      ? null
                      : IconButton(
                          tooltip: 'Copy link',
                          icon: const Icon(Icons.copy_outlined, size: 15),
                          onPressed: () =>
                              Clipboard.setData(ClipboardData(text: line)),
                        ),
                ),
          ],
        );
      }
      return _textView(value, code: mimeType == 'text/html');
    }
    return _Message(icon: _icon(widget.item), title: 'Content received');
  }

  Widget _textView(String text, {bool code = false}) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: code
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                text.isEmpty ? '(empty)' : text,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.7,
                  color: AppTheme.ink,
                ),
              ),
            )
          : SizedBox(
              width: constraints.maxWidth - 32,
              child: SelectableText(
                text.isEmpty ? '(empty)' : text,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.7,
                  color: AppTheme.ink,
                ),
              ),
            ),
    ),
  );

  Widget _metadata(String name, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
        const SizedBox(height: 3),
        SelectableText(
          value,
          style: const TextStyle(fontSize: 12, color: AppTheme.ink),
        ),
      ],
    ),
  );

  Widget _detailBody() {
    final item = widget.item;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _metadata('Type', _kind(item)),
        if (item.mimeType != null) _metadata('MIME type', item.mimeType!),
        if (item case DropFileItem(:final localPath, :final isPromised)) ...[
          _metadata(
            'Location',
            localPath ?? 'Source reference · no local path',
          ),
          _metadata('File promise', '$isPromised'),
          if (item.appleBookmark != null) BookmarkTools(file: item),
        ],
        if (item case DropDirectoryItem(
          :final localPath,
          :final isPromised,
        )) ...[
          _metadata(
            'Location',
            localPath ?? 'Source reference · no local path',
          ),
          _metadata('File promise', '$isPromised'),
        ],
        _metadata(
          'Global position',
          '${widget.event.globalPosition.dx.toStringAsFixed(1)}, ${widget.event.globalPosition.dy.toStringAsFixed(1)}',
        ),
        _metadata(
          'Local position',
          '${widget.event.localPosition.dx.toStringAsFixed(1)}, ${widget.event.localPosition.dy.toStringAsFixed(1)}',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _actions(),
      if (_imageInfo != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          child: Text(
            _imageInfo!,
            style: const TextStyle(fontSize: 11, color: AppTheme.muted),
          ),
        ),
      if (_notice != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          child: Text(
            _notice!,
            style: const TextStyle(fontSize: 12, color: AppTheme.muted),
          ),
        ),
      Expanded(child: _details ? _detailBody() : _body()),
      const Divider(height: 1),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() => _details = !_details),
          icon: Icon(
            _details ? Icons.expand_less : Icons.chevron_right,
            size: 17,
          ),
          label: Text(
            _details ? 'Back to content' : 'Details',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ),
    ],
  );
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    this.description,
    this.busy = false,
  });
  final IconData icon;
  final String title;
  final String? description;
  final bool busy;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(icon, size: 30, color: AppTheme.muted),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppTheme.ink,
            ),
          ),
          if (description != null) ...[
            const SizedBox(height: 8),
            SelectableText(
              description!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppTheme.muted),
            ),
          ],
        ],
      ),
    ),
  );
}

class _Checkerboard extends CustomPainter {
  const _Checkerboard();
  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.save();
    canvas.clipRect(bounds);
    final paint = Paint()..color = const Color(0xFFFAFAFC);
    canvas.drawRect(bounds, paint);
    paint.color = const Color(0xFFEEEFF3);
    for (var y = 0.0; y < size.height; y += 12) {
      for (var x = 0.0; x < size.width; x += 12) {
        if (((x / 12).round() + (y / 12).round()).isEven) {
          canvas.drawRect(Rect.fromLTWH(x, y, 12, 12), paint);
        }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Checkerboard oldDelegate) => false;
}
