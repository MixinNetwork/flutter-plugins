import AVFoundation
import Foundation
import Speech

private let opusDecodedSampleRate: Int32 = 48000

@available(iOS 10.0, macOS 10.15, *)
final class OggOpusSpeechTranscriber {
  enum TranscriberError: Error {
    case speechRecognitionNotAuthorized
    case recognizerUnavailable
    case recognizerCreationFailed
    case audioFormatCreationFailed
    case audioBufferCreationFailed
  }

  private let request = SFSpeechAudioBufferRecognitionRequest()
  private let recognizer: SFSpeechRecognizer
  private let resultHandler: (OggOpusTranscription) -> Void
  private let completionHandler: (Error?) -> Void
  private var recognitionTask: SFSpeechRecognitionTask?
  private var appendedDuration: TimeInterval = 0
  private var completed = false

  init(
    localeIdentifier: String?,
    addsPunctuation: Bool,
    shouldReportPartialResults: Bool,
    resultHandler: @escaping (OggOpusTranscription) -> Void,
    completionHandler: @escaping (Error?) -> Void
  ) throws {
    if SFSpeechRecognizer.authorizationStatus() != .authorized {
      throw TranscriberError.speechRecognitionNotAuthorized
    }

    if let localeIdentifier, !localeIdentifier.isEmpty {
      guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)) else {
        throw TranscriberError.recognizerCreationFailed
      }
      self.recognizer = recognizer
    } else {
      guard let recognizer = SFSpeechRecognizer() else {
        throw TranscriberError.recognizerCreationFailed
      }
      self.recognizer = recognizer
    }

    guard self.recognizer.isAvailable else {
      throw TranscriberError.recognizerUnavailable
    }

    self.resultHandler = resultHandler
    self.completionHandler = completionHandler
    request.shouldReportPartialResults = shouldReportPartialResults
    if #available(iOS 16.0, macOS 13.0, *) {
      request.addsPunctuation = addsPunctuation
    }
  }

  func start() {
    recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
      guard let self else {
        return
      }
      if let result {
        self.resultHandler(OggOpusTranscription(
          text: result.bestTranscription.formattedString,
          isFinal: result.isFinal,
          duration: self.duration
        ))
      }

      if let error {
        self.complete(error)
      } else if result?.isFinal == true {
        self.complete(nil)
      }
    }
  }

  func appendPCMData(_ pcmData: Data, sampleRate: Int32) throws {
    guard !completed, !pcmData.isEmpty else {
      return
    }
    guard let format = AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: Double(sampleRate),
      channels: 1,
      interleaved: false
    ) else {
      throw TranscriberError.audioFormatCreationFailed
    }

    let frameCount = AVAudioFrameCount(pcmData.count / MemoryLayout<Int16>.size)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
      throw TranscriberError.audioBufferCreationFailed
    }
    buffer.frameLength = frameCount
    guard let channel = buffer.int16ChannelData?[0] else {
      throw TranscriberError.audioBufferCreationFailed
    }
    pcmData.copyBytes(
      to: UnsafeMutableRawBufferPointer(
        start: channel,
        count: pcmData.count
      )
    )
    appendedDuration += TimeInterval(frameCount) / TimeInterval(sampleRate)
    request.append(buffer)
  }

  func finish() {
    guard !completed else {
      return
    }
    request.endAudio()
  }

  func cancel() {
    guard !completed else {
      return
    }
    completed = true
    recognitionTask?.cancel()
    recognitionTask = nil
  }

  private var duration: TimeInterval? {
    guard appendedDuration > 0 else {
      return nil
    }
    return appendedDuration
  }

  private func complete(_ error: Error?) {
    guard !completed else {
      return
    }
    completed = true
    recognitionTask = nil
    completionHandler(error)
  }
}

@available(iOS 10.0, macOS 10.15, *)
func transcribeOggOpusFile(
  path: String,
  localeIdentifier: String?,
  addsPunctuation: Bool,
  resultHandler: @escaping (Result<OggOpusTranscription, Error>) -> Void
) throws -> OggOpusSpeechTranscriber {
  var finalTranscription = OggOpusTranscription(text: "", isFinal: false, duration: nil)
  let transcriber = try OggOpusSpeechTranscriber(
    localeIdentifier: localeIdentifier,
    addsPunctuation: addsPunctuation,
    shouldReportPartialResults: false,
    resultHandler: { transcription in
      finalTranscription = transcription
    },
    completionHandler: { error in
      if let error {
        resultHandler(.failure(error))
      } else {
        resultHandler(.success(finalTranscription))
      }
    }
  )

  transcriber.start()
  DispatchQueue.global(qos: .userInitiated).async {
    do {
      let reader = try OggOpusReader(fileAtPath: path)
      while !reader.didReachEnd {
        let pcmData = try reader.pcmData(maxLength: 4096)
        if !pcmData.isEmpty {
          try transcriber.appendPCMData(pcmData, sampleRate: opusDecodedSampleRate)
        }
      }
      transcriber.finish()
    } catch {
      transcriber.cancel()
      resultHandler(.failure(error))
    }
  }

  return transcriber
}
