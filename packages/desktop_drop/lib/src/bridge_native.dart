import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'bridge.dart';
import 'bridge_bindings.g.dart';
import 'drop_coordinator.dart';
import 'drop_item.dart';
import 'drop_offer.dart';
import 'drop_target.dart';
import 'file_tree.dart';
import 'native_transport.dart';
import 'source_reader.dart';
import 'virtual_directory.dart';

final _connections = <int, _NativeBridge>{};
bool _handlerInstalled = false;

DropBridge createDropBridge(int view, DropCoordinator coordinator) {
  if (!_handlerInstalled) {
    NativeTransport.instance.onEvent = (call) async {
      final map = (call.arguments as Map).cast<Object?, Object?>();
      final connection = _connections[map['view']];
      if (connection == null || connection._disposed) {
        return call.method == 'drop' ? false : {'target': 0, 'operation': 0};
      }
      if (call.method == 'query') {
        if ((map['generation'] as int? ?? 0) != connection.generation) {
          return {'target': 0, 'operation': 0};
        }
        final selection = connection._decideMap(map);
        return {
          'target': selection.target,
          'operation': (selection.operation?.index ?? -1) + 1,
        };
      }
      if (call.method == 'feedback' ||
          call.method == 'drop' ||
          call.method == 'exit') {
        if ((map['generation'] as int? ?? 0) != connection.generation) {
          return false;
        }
        return await connection._event(call.method, map);
      }
      throw MissingPluginException('Unknown desktop_drop event ${call.method}');
    };
    _handlerInstalled = true;
  }
  final bridge = _NativeBridge(view, coordinator);
  _connections[view] = bridge;
  return bridge;
}

class _NativeBridge implements DropBridge {
  _NativeBridge(this.view, this.coordinator);
  final int view;
  final DropCoordinator coordinator;
  bool _disposed = false;
  int _context = 0;
  int generation = 0;
  ReceivePort? _port;
  NativeCallable<DDDecideFunction>? _callback;
  DropBridgeBindings? _bindings;
  int? _offerSession;
  DropOffer? _offer;
  int? _operationMask;
  int _feedbackRequest = 0;

  // Compact native messages refer to one decoded offer per drag session.
  DropOffer? _resolveOffer(int session, Map<Object?, Object?> event) {
    final data = event['offer'] as Map?;
    if (data != null) {
      _offer = DropOffer.fromMap(data.cast<Object?, Object?>());
      _offerSession = session;
      _operationMask = null;
    }
    if (_offerSession != session) return null;
    var offer = _offer;
    if (offer == null) return null;
    if (event['operationMask'] case final int mask) {
      if (_operationMask == mask) return offer;
      final operations = <DropOperation>{
        if ((mask & 1) != 0) DropOperation.copy,
        if ((mask & 2) != 0) DropOperation.move,
        if ((mask & 4) != 0) DropOperation.link,
      };
      if (!setEquals(offer.allowedOperations, operations)) {
        offer = DropOffer(
          items: offer.items,
          isComplete: offer.isComplete,
          allowedOperations: operations,
        );
        _offer = offer;
      }
      _operationMask = mask;
    }
    return offer;
  }

  DropSelection _decide(
    Map<Object?, Object?> event,
    int session,
    Offset position,
  ) {
    final offer = _resolveOffer(session, event);
    // Native adapters resend a full offer on a cache miss.
    if (offer == null) return (target: -1, operation: null);
    return coordinator.decide(view, offer, position);
  }

  DropSelection _safeDecision(
    Uint8List bytes,
    int session,
    double x,
    double y,
  ) {
    try {
      return _decide(
        (const StandardMessageCodec().decodeMessage(
          ByteData.sublistView(bytes),
        ) as Map).cast<Object?, Object?>(),
        session,
        Offset(x, y),
      );
    } catch (error, stack) {
      _report(error, stack);
      return (target: 0, operation: null);
    }
  }

  DropSelection _decideMap(Map<Object?, Object?> event) {
    try {
      return _decide(
        event,
        event['session'] as int,
        Offset((event['x'] as num).toDouble(), (event['y'] as num).toDouble()),
      );
    } catch (error, stack) {
      _report(error, stack);
      return (target: 0, operation: null);
    }
  }

  Future<bool> _event(String method, Map<Object?, Object?> event) async {
    final session = event['session'] as int;
    if (method == 'exit') {
      coordinator.exit(view, session);
      return false;
    }
    if (method == 'feedback') {
      final request = event['request'] as int;
      if (request <= _feedbackRequest) return false;
      if (event['phase'] == 2) {
        _feedbackRequest = request;
        coordinator.exit(view);
        return false;
      }
    }
    final offer = _resolveOffer(session, event);
    if (offer == null) return false;
    final position = Offset(
      (event['x'] as num).toDouble(),
      (event['y'] as num).toDouble(),
    );
    final selection = (
      target: event['target'] as int,
      operation: switch (event['operation']) {
        1 => DropOperation.copy,
        2 => DropOperation.move,
        3 => DropOperation.link,
        _ => null,
      },
    );
    if (method == 'feedback') {
      _feedbackRequest = event['request'] as int;
      return coordinator.feedback(view, session, selection, offer, position);
    }
    final details = coordinator.details(view, selection, offer, position);
    if (details == null) return false;
    final source = {'view': view, 'generation': generation, 'session': session};
    return coordinator.drop(
      view,
      selection.target,
      DropDetails(
        localPosition: details.localPosition,
        globalPosition: details.globalPosition,
        operation: selection.operation!,
        items: _items((event['offer'] as Map).cast<Object?, Object?>(), source),
      ),
      session: session,
    );
  }

  List<DropItem> _items(
    Map<Object?, Object?> offer,
    Map<Object?, Object?> context,
  ) => [
    for (final file in fileTree(
      (offer['files'] as List? ?? const []).cast<Map>(),
    ))
      _file(file, context),
    for (final string in (offer['strings'] as List? ?? const []).cast<Map>())
      if (string['value'] case final String value)
        DropStringItem(mimeType: string['mimeType'] as String, value: value),
  ];

  DropItem _file(Map file, Map<Object?, Object?> context) {
    final name = file['name'] as String? ?? '';
    final source = {
      'view': context['view'],
      'generation': context['generation'],
      'session': context['session'],
      'source': file['source'],
      'name': name,
      if (file['resolvePath'] == true) 'resolvePath': true,
    };
    final bookmark = file['apple-bookmark'] as Uint8List?;
    final promised = file['isPromised'] as bool? ?? false;
    if (file['isDirectory'] == true) {
      final path = file['path'] as String?;
      final children = (file['children'] as List?)?.cast<Map>();
      return DropDirectoryItem(
        directory: children != null
            ? virtualDirectory(name, () async* {
                for (final child in children) {
                  yield switch (_file(child, context)) {
                    DropFileItem(:final file) => file,
                    DropDirectoryItem(:final directory) => directory,
                    DropStringItem() => throw StateError(
                      'Not a directory entry',
                    ),
                  };
                }
              })
            : file['source'] != null
            ? sourceDirectory(source)
            : XDirectory.fileSystem(path: path!),
        name: name,
        localPath: path,
        appleBookmark: bookmark,
        isPromised: promised,
      );
    }
    if (file['source'] != null) {
      return DropFileItem(
        file: sourceFile(source, name),
        name: name,
        mimeType: file['mimeType'] as String?,
        isPromised: promised,
      );
    }
    final path = file['path'] as String;
    return DropFileItem.fromPath(
      path,
      name: name,
      mimeType: file['mimeType'] as String?,
      appleBookmark: bookmark,
      isPromised: promised,
    );
  }

  @override
  Future<void> initialize() async {
    final descriptor = await NativeTransport.instance.invoke<Map>(
      'initialize',
      {'view': view},
    );
    if (_disposed) return;
    if (descriptor == null || descriptor['view'] != view) {
      throw StateError('desktop_drop could not bind Flutter view $view');
    }
    // GTK and Android can request a synchronous Dart predicate through an
    // asynchronous FFI reply. They do not block their main loop.
    if (!descriptor.containsKey('context')) {
      generation = descriptor['generation'] as int? ?? 0;
      return;
    }
    _context = descriptor['context'] as int;
    _bindings = NativeTransport.instance.bindings;
    _callback = NativeCallable<DDDecideFunction>.isolateLocal((
      Pointer<DDRequest> pointer,
      Pointer<DDDecision> result,
    ) {
      final request = pointer.ref;
      if (_disposed || request.generation != generation) return;
      final selection = _safeDecision(
        request.payload.asTypedList(request.length),
        request.session,
        request.x,
        request.y,
      );
      result.ref
        ..target = selection.target
        ..operation = (selection.operation?.index ?? -1) + 1;
    });
    _port = ReceivePort()
      ..listen((dynamic message) {
        final data = message as List;
        if (_disposed || data[0] != _context || data[1] != generation) return;
        final selection = _safeDecision(
          data[8] as Uint8List,
          data[4] as int,
          (data[6] as num).toDouble(),
          (data[7] as num).toDouble(),
        );
        _bindings!.dd_bridge_complete(
          _context,
          generation,
          data[2] as int,
          selection.target,
          (selection.operation?.index ?? -1) + 1,
        );
      });
    generation = _bindings!.dd_bridge_register(
      _context,
      NativeApi.initializeApiDLData,
      _port!.sendPort.nativePort,
      _callback!.nativeFunction,
      ui.isRunningOnPlatformThread ? 1 : 0,
      view,
    );
    if (generation == 0) {
      dispose();
      throw StateError(
        'desktop_drop could not initialize the native Dart bridge',
      );
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (identical(_connections[view], this)) _connections.remove(view);
    if (generation != 0) _bindings?.dd_bridge_unregister(_context, generation);
    _port?.close();
    _callback?.close();
  }
}

void _report(Object error, StackTrace stack) {
  scheduleMicrotask(
    () => FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'desktop_drop',
        context: ErrorDescription(
          'while deciding whether to accept an OS drop',
        ),
      ),
    ),
  );
}
