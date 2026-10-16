import 'bridge.dart';
import 'drop_coordinator.dart';

DropBridge createDropBridge(int view, DropCoordinator coordinator) =>
    _WebBridge();

class _WebBridge implements DropBridge {
  @override
  Future<void> initialize() async {}
  @override
  void dispose() {}
}
