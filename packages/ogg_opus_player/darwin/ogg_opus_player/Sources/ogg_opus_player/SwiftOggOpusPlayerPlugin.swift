#if os(iOS)
  import Flutter
  import Speech
  import UIKit
#elseif os(macOS)
  import FlutterMacOS
  import Speech
#endif

// key -> playerId
// value -> OggOpusPlayer
private var playerDictionary: [Int: OggOpusPlayer] = [:]

private var recorderDictionary: [Int: OggOpusRecorder] = [:]

@available(iOS 10.0, macOS 10.15, *)
private var speechTranscriberDictionary: [Int: OggOpusSpeechTranscriber] = [:]

public class SwiftOggOpusPlayerPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
      let channel = FlutterMethodChannel(name: "ogg_opus_player", binaryMessenger: registrar.messenger())
    #elseif os(macOS)
      let channel = FlutterMethodChannel(name: "ogg_opus_player", binaryMessenger: registrar.messenger)
    #endif
    let instance = SwiftOggOpusPlayerPlugin(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  let channel: FlutterMethodChannel

  public init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
  }

  private func handlePlayerStateChanged(id: Int, _ player: OggOpusPlayer) {
    channel.invokeMethod("onPlayerStateChanged", arguments: [
      "state": player.status.rawValue,
      "position": player.currentTime,
      "playerId": id,
      "updateTime": systemUptime(),
      "speed": player.playRate,
    ])
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "speechRecognitionAuthorizationStatus":
      if #available(iOS 10.0, macOS 10.15, *) {
        result(speechRecognitionAuthorizationStatus())
      } else {
        result("unavailable")
      }
    case "requestSpeechRecognitionAuthorization":
      if #available(iOS 10.0, macOS 10.15, *) {
        requestSpeechRecognitionAuthorization(result: result)
      } else {
        result(FlutterError(code: "speech_recognition_unavailable", message: "Speech recognition requires iOS 10.0 or macOS 10.15 or later", details: nil))
      }
    case "transcribeFile":
      if #available(iOS 10.0, macOS 10.15, *) {
        transcribeFile(call, result: result)
      } else {
        result(FlutterError(code: "speech_recognition_unavailable", message: "Speech recognition requires iOS 10.0 or macOS 10.15 or later", details: nil))
      }
    case "create":
      guard let path = call.arguments as? String else {
        result(FlutterError(code: "1", message: "path can not be null", details: nil))
        break
      }
      do {
        let player = try OggOpusPlayer(path: path)
        let id = generatedPlayerId()
        player.onStatusChanged = { _ in
          self.handlePlayerStateChanged(id: id, player)
        }
        playerDictionary[id] = player
        result(id)
      } catch {
        result(FlutterError(code: "2", message: error.localizedDescription, details: nil))
      }
    case "play":
      if let playerId = call.arguments as? Int {
        playerDictionary[playerId]?.play()
      }
      result(nil)
    case "pause":
      if let playerId = call.arguments as? Int {
        playerDictionary[playerId]?.pause()
      }
      result(nil)
    case "stop":
      if let playerId = call.arguments as? Int {
        playerDictionary[playerId]?.stop()
        playerDictionary.removeValue(forKey: playerId)
      }
      result(nil)
    case "setPlaybackSpeed":
      if let args = call.arguments as? [String: Any],
         let playerId = args["playerId"] as? Int,
         let speed = args["speed"] as? Double {
        if let player = playerDictionary[playerId] {
          player.playRate = Float(speed)
          handlePlayerStateChanged(id: playerId, player)
        }
      }
      result(nil)
    case "createRecorder":
      let path: String?
      let enableTranscription: Bool
      let transcriptionLocaleIdentifier: String?
      let transcriptionAddsPunctuation: Bool
      if let args = call.arguments as? [String: Any] {
        path = args["path"] as? String
        enableTranscription = args["enableTranscription"] as? Bool ?? false
        transcriptionLocaleIdentifier = args["transcriptionLocaleIdentifier"] as? String
        transcriptionAddsPunctuation = args["transcriptionAddsPunctuation"] as? Bool ?? true
      } else {
        path = call.arguments as? String
        enableTranscription = false
        transcriptionLocaleIdentifier = nil
        transcriptionAddsPunctuation = true
      }

      guard let path else {
        result(FlutterError(code: "3", message: "recorder path can not be null", details: nil))
        break
      }

      let recorder = OggOpusRecorder(path: path)
      let id = generatedPlayerId()
      recorder.delegate = PluginOggOpusRecorderDelegate(channel: channel, recorderId: id)
      if enableTranscription {
        if #available(iOS 10.0, macOS 10.15, *) {
          recorder.transcriptionConfiguration = OggOpusRecorder.TranscriptionConfiguration(
            localeIdentifier: transcriptionLocaleIdentifier,
            addsPunctuation: transcriptionAddsPunctuation
          )
        } else {
          result(FlutterError(code: "speech_recognition_unavailable", message: "Speech recognition requires iOS 10.0 or macOS 10.15 or later", details: nil))
          break
        }
      }
      recorderDictionary[id] = recorder
      result(id)
    case "startRecord":
      if let id = call.arguments as? Int {
        recorderDictionary[id]?.record(for: TimeInterval.infinity)
      }
      result(nil)
    case "stopRecord":
      if let id = call.arguments as? Int {
        recorderDictionary[id]?.stop()
      }
      result(nil)
    case "destroyRecorder":
      if let id = call.arguments as? Int {
        recorderDictionary.removeValue(forKey: id)
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  @available(iOS 10.0, macOS 10.15, *)
  private func speechRecognitionAuthorizationStatus() -> String {
    switch SFSpeechRecognizer.authorizationStatus() {
    case .authorized:
      return "authorized"
    case .denied:
      return "denied"
    case .restricted:
      return "restricted"
    case .notDetermined:
      return "notDetermined"
    @unknown default:
      return "unknown"
    }
  }

  @available(iOS 10.0, macOS 10.15, *)
  private func requestSpeechRecognitionAuthorization(result: @escaping FlutterResult) {
    switch SFSpeechRecognizer.authorizationStatus() {
    case .authorized:
      result(nil)
    case .notDetermined:
      SFSpeechRecognizer.requestAuthorization { status in
        DispatchQueue.main.async {
          if status == .authorized {
            result(nil)
          } else {
            result(FlutterError(code: "speech_recognition_denied", message: "Speech recognition authorization was not granted", details: nil))
          }
        }
      }
    case .denied:
      result(FlutterError(code: "speech_recognition_denied", message: "Speech recognition authorization was denied", details: nil))
    case .restricted:
      result(FlutterError(code: "speech_recognition_restricted", message: "Speech recognition is restricted", details: nil))
    @unknown default:
      result(FlutterError(code: "speech_recognition_unknown", message: "Unknown speech recognition authorization status", details: nil))
    }
  }

  @available(iOS 10.0, macOS 10.15, *)
  private func transcribeFile(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let path = args["path"] as? String else {
      result(FlutterError(code: "invalid_arguments", message: "path can not be null", details: nil))
      return
    }
    let localeIdentifier = args["localeIdentifier"] as? String
    let addsPunctuation = args["addsPunctuation"] as? Bool ?? true
    let id = generatedPlayerId()

    do {
      let transcriber = try transcribeOggOpusFile(
        path: path,
        localeIdentifier: localeIdentifier,
        addsPunctuation: addsPunctuation
      ) { transcriptionResult in
        DispatchQueue.main.async {
          speechTranscriberDictionary.removeValue(forKey: id)
          switch transcriptionResult {
          case let .success(transcription):
            result(transcription.dictionary)
          case let .failure(error):
            result(FlutterError(code: "transcription_failed", message: error.localizedDescription, details: nil))
          }
        }
      }
      speechTranscriberDictionary[id] = transcriber
    } catch {
      result(FlutterError(code: "transcription_failed", message: error.localizedDescription, details: nil))
    }
  }
}

private var _lastGeneratedId = 0

private func generatedPlayerId() -> Int {
  _lastGeneratedId += 1
  return _lastGeneratedId
}

private func systemUptime() -> Int {
  var spec = timespec()
  clock_gettime(CLOCK_UPTIME_RAW, &spec)
  return spec.tv_sec * 1000 + spec.tv_nsec / 1000000
}

class PluginOggOpusRecorderDelegate: OggOpusRecorderDelegate {
  let channel: FlutterMethodChannel
  let recorderId: Int

  init(channel: FlutterMethodChannel, recorderId: Int) {
    self.channel = channel
    self.recorderId = recorderId
  }

  func oggOpusRecorderIsWaitingForActivation(_ recorder: OggOpusRecorder) {
  }

  func oggOpusRecorderDidStartRecording(_ recorder: OggOpusRecorder) {
  }

  func oggOpusRecorder(_ recorder: OggOpusRecorder, didCancelRecordingForReason reason: OggOpusRecorder.CancelledReason, userInfo: [String: Any]?) {
    channel.invokeMethod(
      "onRecorderCanceled",
      arguments: [
        "recorderId": recorderId,
        "reason": reason.rawValue,
      ],
      result: nil
    )
  }

  func oggOpusRecorder(_ recorder: OggOpusRecorder, didFailRecordingWithError error: Error) {
    channel.invokeMethod(
      "onRecorderStartFailed",
      arguments: [
        "error": error.localizedDescription,
        "recorderId": recorderId,
      ],
      result: nil
    )
  }

  func oggOpusRecorder(_ recorder: OggOpusRecorder, didFinishRecordingWithMetadata data: AudioMetadata) {
    debugPrint("onRecorderFinished: ")
    channel.invokeMethod("onRecorderFinished", arguments: [
      "duration": NSNumber(value: data.duration),
      "waveform": FlutterStandardTypedData(bytes: data.waveform),
      "recorderId": recorderId,
    ], result: nil)
  }

  func oggOpusRecorder(_ recorder: OggOpusRecorder, didReceiveTranscription transcription: OggOpusTranscription) {
    var arguments = transcription.dictionary
    arguments["recorderId"] = recorderId
    channel.invokeMethod("onRecorderTranscription", arguments: arguments, result: nil)
  }

  func oggOpusRecorder(_ recorder: OggOpusRecorder, didFailTranscriptionWithError error: Error) {
    channel.invokeMethod("onRecorderTranscriptionFailed", arguments: [
      "error": error.localizedDescription,
      "recorderId": recorderId,
    ], result: nil)
  }

  func oggOpusRecorderDidDetectAudioSessionInterruptionEnd(_ recorder: OggOpusRecorder) {
  }
}
