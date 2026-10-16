import 'drop_offer.dart';

typedef DropSelection = ({int target, DropOperation operation});

abstract interface class DropBridge {
  Future<void> initialize();
  void dispose();
}
