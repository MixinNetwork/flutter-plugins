import 'dart:ui';

abstract class WindowController {
  Future<void> close();

  Future<void> show();

  Future<void> hide();

  Future<void> setSize(Size size);

  Future<void> setPosition(Offset position);

  Future<void> center();

  Future<void> setTitle(String title);
}
