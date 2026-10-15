import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'bridge.dart';
import 'bridge_stub.dart' if (dart.library.ffi) 'bridge_native.dart';
import 'drop_item.dart';
import 'drop_offer.dart';
import 'drop_target.dart';

abstract interface class DropTargetClient {
  int get id;
  int get view;
  bool get enabled;
  RenderBox? get box;
  bool accepts(DropEventDetails details);
  void entered(DropEventDetails details);
  void updated(DropEventDetails details);
  void exited(DropEventDetails details);
  void dropped(DropDoneDetails details);
}

class _View {
  _View(this.bridge);
  final DropBridge bridge;
  final targets = <int>{};
  int? hovering;
  int? session;
  int request = 0;
  DropEventDetails? details;
}

/// Owns selection and delivery for all native adapters and the browser.
/// Public widget tests use the same decision/delivery seam as native callbacks.
class DropCoordinator {
  static final instance = DropCoordinator();
  static int _nextTarget = 1;
  static int nextTargetId() => _nextTarget++;

  final _targets = <int, DropTargetClient>{};
  final _views = <int, _View>{};

  void add(DropTargetClient target) {
    _targets[target.id] = target;
    final view = _views.putIfAbsent(target.view, () {
      final bridge = createDropBridge(target.view, decide, platformEvent);
      unawaited(
        bridge.initialize().catchError((Object error, StackTrace stack) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stack,
              library: 'desktop_drop',
              context: ErrorDescription(
                'while attaching an OS drop destination',
              ),
            ),
          );
        }),
      );
      return _View(bridge);
    });
    view.targets.add(target.id);
  }

  void remove(DropTargetClient target) {
    _targets.remove(target.id);
    final view = _views[target.view];
    if (view == null) return;
    if (view.hovering == target.id) view.hovering = null;
    view.targets.remove(target.id);
    if (view.targets.isEmpty) {
      _views.remove(target.view);
      view.bridge.dispose();
    }
  }

  void disabled(DropTargetClient target) {
    final view = _views[target.view];
    if (view?.hovering != target.id) return;
    view!.hovering = null;
    final details = view.details;
    // didUpdateWidget runs during a build. User hover callbacks can setState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (identical(_targets[target.id], target) && details != null) {
        target.exited(details);
      }
    });
  }

  int decide(int view, DropOffer offer, Offset position) {
    if (!_views.containsKey(view)) return 0;
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, position, view);
    final visited = <int>{};
    for (final entry in result.path) {
      final render = entry.target;
      if (render is! RenderMetaData || render.metaData is! DropTargetClient) {
        continue;
      }
      final target = render.metaData as DropTargetClient;
      if (target.view != view ||
          !target.enabled ||
          !identical(_targets[target.id], target) ||
          !visited.add(target.id)) {
        continue;
      }
      final details = _details(target, offer, position);
      if (details == null) continue;
      try {
        if (target.accepts(details)) return target.id;
      } catch (error, stack) {
        scheduleMicrotask(
          () => FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stack,
              library: 'desktop_drop',
              context: ErrorDescription('in DropTarget.onWillAccept'),
            ),
          ),
        );
      }
    }
    return 0;
  }

  DropEventDetails? _details(
    DropTargetClient target,
    DropOffer offer,
    Offset position,
  ) {
    final box = target.box;
    if (box == null || !box.attached || !box.hasSize) return null;
    return DropEventDetails(
      offer: offer,
      globalPosition: position,
      localPosition: box.globalToLocal(position),
    );
  }

  void platformEvent(Map<Object?, Object?> event) {
    final viewId = event['view'] as int;
    final view = _views[viewId];
    if (view == null) return;
    final session = event['session'] as int;
    final kind = event['event'];
    if (kind == 'exit') {
      if (view.session == session) _exit(view);
      return;
    }
    final position = Offset(
      (event['x'] as num).toDouble(),
      (event['y'] as num).toDouble(),
    );
    final data = (event['offer'] as Map).cast<Object?, Object?>();
    final offer = DropOffer.fromMap(data);
    final target = _targets[event['target']];
    if (kind == 'drop') {
      if (target == null || target.view != viewId || !target.enabled) return;
      final details = _details(target, offer, position);
      if (details == null) return;
      target.dropped(
        DropDoneDetails(
          offer: offer,
          localPosition: details.localPosition,
          globalPosition: position,
          files: (event['items'] as List<DropItem>?) ?? _files(data),
          rawText: data['rawText'] as String?,
        ),
      );
      return;
    }
    final request = event['request'] as int;
    if (request <= view.request) return;
    view.request = request;
    if (view.session != session) _exit(view);
    view.session = session;
    if (event['phase'] == 2) {
      _exit(view);
      return;
    }
    final selected = target != null && target.enabled && target.view == viewId
        ? target
        : null;
    if (view.hovering != selected?.id) {
      _exit(view);
      if (selected != null) {
        final details = _details(selected, offer, position);
        if (details == null) return;
        view.hovering = selected.id;
        view.details = details;
        selected.entered(details);
      }
    } else if (selected != null) {
      final details = _details(selected, offer, position);
      if (details == null) return;
      view.details = details;
      selected.updated(details);
    }
  }

  void _exit(_View view) {
    final previous = _targets[view.hovering];
    final details = view.details;
    view.hovering = null;
    view.details = null;
    if (previous != null && details != null) previous.exited(details);
  }

  List<DropItem> _files(Map<Object?, Object?> offer) =>
      (offer['files'] as List? ?? const []).cast<Map>().map((file) {
        final path = file['path'] as String;
        final name = file['name'] as String?;
        final bookmark = file['apple-bookmark'] as Uint8List?;
        final promised = file['isPromised'] as bool? ?? false;
        if (file['isDirectory'] == true) {
          return DropItemDirectory(
            path,
            const [],
            name: name,
            extraAppleBookmark: bookmark,
            fromPromise: promised,
          );
        }
        return DropItemFile(
          path,
          name: name,
          mimeType: file['mimeType'] as String?,
          extraAppleBookmark: bookmark,
          fromPromise: promised,
        );
      }).toList();
}
