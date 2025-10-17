//
//  Generated file. Do not edit.
//

import FlutterMacOS
import Foundation

import audio_session
import ogg_opus_player
import path_provider_foundation

func RegisterGeneratedPlugins(registry: FlutterPluginRegistry) {
  AudioSessionPlugin.register(with: registry.registrar(forPlugin: "AudioSessionPlugin"))
  OggOpusPlayerPlugin.register(with: registry.registrar(forPlugin: "OggOpusPlayerPlugin"))
  PathProviderPlugin.register(with: registry.registrar(forPlugin: "PathProviderPlugin"))
}
