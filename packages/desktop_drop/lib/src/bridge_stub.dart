import 'bridge.dart';

DropBridge createDropBridge(
  int view,
  DropDecision decide,
  DropPlatformEvent event,
) => _WebBridge();

class _WebBridge implements DropBridge {
  @override
  int get generation => 0;
  @override
  Future<void> initialize() async {}
  @override
  void dispose() {}
}
