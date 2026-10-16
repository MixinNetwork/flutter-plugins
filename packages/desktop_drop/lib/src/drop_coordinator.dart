import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'bridge.dart';
import 'bridge_stub.dart' if (dart.library.ffi) 'bridge_native.dart';
import 'drop_offer.dart';
import 'drop_target.dart';

abstract interface class DropTargetClient {
  int get id;
  int get view;
  bool get enabled;
  RenderBox? get box;
  DropOperation decide(DropEventDetails details);
  void entered(DropEventDetails details);
  void updated(DropEventDetails details);
  void exited(DropEventDetails details);
  FutureOr<void> dropped(DropEvent details);
}

class _View {
  _View(this.bridge);
  final DropBridge bridge;
  final targets = <int>{};
  int? hovering;
  int? session;
  DropEventDetails? details;
}

/// Owns selection and delivery for all native adapters and the browser.
/// Public widget tests use the same decision/delivery seam as native callbacks.
class DropCoordinator with WidgetsBindingObserver {
  DropCoordinator() {
    WidgetsBinding.instance.addObserver(this);
  }

  static final instance = DropCoordinator();
  static int _nextTarget = 1;
  static int nextTargetId() => _nextTarget++;

  final _targets = <int, DropTargetClient>{};
  final _views = <int, _View>{};

  @override
  void didChangeMetrics() {
    final liveViews = WidgetsBinding.instance.platformDispatcher.views
        .map((view) => view.viewId)
        .toSet();
    final removed = _views.keys.where((id) => !liveViews.contains(id)).toList();
    for (final id in removed) {
      final view = _views.remove(id)!;
      for (final target in view.targets) {
        _targets.remove(target);
      }
      view.bridge.dispose();
    }
  }

  void add(DropTargetClient target) {
    _targets[target.id] = target;
    final viewId = target.view;
    final view = _views.putIfAbsent(viewId, () {
      final bridge = createDropBridge(viewId, this);
      final view = _View(bridge);
      // A failed initialization can leave other targets mounted in this view.
      view.targets.addAll(
        _targets.values
            .where((target) => target.view == viewId)
            .map((target) => target.id),
      );
      unawaited(
        bridge.initialize().catchError((Object error, StackTrace stack) {
          if (identical(_views[viewId], view)) _views.remove(viewId);
          bridge.dispose();
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
      return view;
    });
    view.targets.add(target.id);
  }

  void remove(DropTargetClient target) {
    _targets.remove(target.id);
    final view = _views[target.view];
    if (view == null) return;
    if (view.hovering == target.id) {
      view.hovering = null;
      view.details = null;
    }
    view.targets.remove(target.id);
    if (view.targets.isEmpty) {
      // Page changes must not invalidate sources already delivered to onDrop.
      // The bridge is released when the Flutter view is removed instead.
      view.details = null;
      view.session = null;
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

  DropSelection decide(int view, DropOffer offer, Offset position) {
    const rejected = (target: 0, operation: DropOperation.reject);
    final state = _views[view];
    if (state == null || state.targets.isEmpty) return rejected;
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
        final operation = target.decide(details);
        if (operation != DropOperation.reject &&
            offer.allowedOperations.contains(operation)) {
          return (target: target.id, operation: operation);
        }
      } catch (error, stack) {
        scheduleMicrotask(
          () => FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stack,
              library: 'desktop_drop',
              context: ErrorDescription('in DropTarget.onDropDecision'),
            ),
          ),
        );
      }
    }
    return rejected;
  }

  DropEventDetails? _details(
    DropTargetClient target,
    DropOffer offer,
    Offset position, [
    DropOperation operation = DropOperation.reject,
  ]) {
    final box = target.box;
    if (box == null || !box.attached || !box.hasSize) return null;
    return DropEventDetails(
      offer: offer,
      globalPosition: position,
      localPosition: box.globalToLocal(position),
      operation: operation,
    );
  }

  DropEventDetails? details(
    int viewId,
    DropSelection selection,
    DropOffer offer,
    Offset position,
  ) {
    final target = _targets[selection.target];
    if (target == null ||
        target.view != viewId ||
        !target.enabled ||
        !offer.allowedOperations.contains(selection.operation)) {
      return null;
    }
    return _details(target, offer, position, selection.operation);
  }

  void exit(int viewId, [int? session]) {
    final view = _views[viewId];
    if (view == null) return;
    if (session == null || view.session == session) _exit(view);
  }

  Future<bool> drop(int viewId, int targetId, DropEvent event) async {
    final target = _targets[targetId];
    if (target == null ||
        target.view != viewId ||
        !target.enabled ||
        !event.allowedOperations.contains(event.operation)) {
      return false;
    }
    final box = target.box;
    if (box == null || !box.attached || !box.hasSize) return false;
    try {
      await target.dropped(event);
      return true;
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'desktop_drop',
          context: ErrorDescription('in DropTarget.onDrop'),
        ),
      );
      return false;
    }
  }

  bool feedback(
    int viewId,
    int session,
    DropSelection selection,
    DropOffer offer,
    Offset position,
  ) {
    final view = _views[viewId];
    if (view == null) return false;
    if (view.session != session) _exit(view);
    view.session = session;
    final target = _targets[selection.target];
    final selected =
        target != null &&
            target.enabled &&
            target.view == viewId &&
            offer.allowedOperations.contains(selection.operation)
        ? target
        : null;
    if (view.hovering != selected?.id) {
      _exit(view);
      if (selected != null) {
        final details = this.details(viewId, selection, offer, position);
        if (details == null) return false;
        view.hovering = selected.id;
        view.details = details;
        selected.entered(details);
      }
    } else if (selected != null) {
      final details = this.details(viewId, selection, offer, position);
      if (details == null) return false;
      view.details = details;
      selected.updated(details);
    }
    return true;
  }

  void _exit(_View view) {
    final previous = _targets[view.hovering];
    final details = view.details;
    view.hovering = null;
    view.details = null;
    if (previous != null && details != null) previous.exited(details);
  }
}
