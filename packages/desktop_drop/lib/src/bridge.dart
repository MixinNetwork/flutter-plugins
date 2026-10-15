import 'package:flutter/widgets.dart';

import 'drop_offer.dart';

typedef DropDecision = int Function(int view, DropOffer offer, Offset position);
typedef DropPlatformEvent = void Function(Map<Object?, Object?> event);

abstract interface class DropBridge {
  int get generation;
  Future<void> initialize();
  void dispose();
}
