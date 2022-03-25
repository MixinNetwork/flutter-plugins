import 'dart:io';

import 'package:flutter/foundation.dart';

import 'player_plugin_impl.dart';
import 'player_ffi_impl.dart';
import 'player_state.dart';

abstract class OggOpusPlayer {
  OggOpusPlayer.create();

  factory OggOpusPlayer(String path) {
    if (Platform.isIOS || Platform.isMacOS) {
      return OggOpusPlayerPluginImpl(path);
    } else if (Platform.isLinux || Platform.isWindows) {
      return OggOpusPlayerFfiImpl(path);
    }
    throw UnsupportedError('Platform not supported');
  }

  void pause();

  void play();

  void dispose();

  ValueListenable<PlayerState> get state;

  /// Current playing position, in seconds.
  double get currentPosition;
}
