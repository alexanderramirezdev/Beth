//
//  SpeechRecognizer.swift
//  Beth
//
//  THE EARS.
//
//  Microphone audio becomes text using Apple's Speech framework:
//
//    Microphone -> AVAudioEngine -> recognition request -> text results
//
//  IMPORTANT DIFFERENCE FROM iOS AND visionOS: macOS has no
//  AVAudioSession. Audio routing is handled by the system, so there is
//  no session to configure. Microphone permission also uses a different
//  API here: AVCaptureDevice rather than AVAudioApplication.
//
//  This is a good example of why "just port it" is rarely just porting.
//  The concepts carry over, the specific APIs do not.
//
//  Permissions: macOS needs BOTH an Info.plist usage string AND the
//  Audio Input sandbox capability. See the README.
//

import Foundation
import Speech
import AVFoundation

final class SpeechRecognizer {

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// Starts listening and returns a stream of transcript updates.
    /// Each value is the FULL transcript so far.
    func startTranscribing() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                // Ask for permission (first launch only; the system
                // remembers the answer afterward).
                let speechAuthorized = await Self.requestSpeechPermission()
                let micAuthorized = await AVCaptureDevice.requestAccess(for: .audio)

                guard speechAuthorized, micAuthorized else {
                    continuation.finish(throwing: RecognizerError.notAuthorized)
                    return
                }

                do {
                    try self.beginSession(continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func beginSession(
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) throws {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true // live captions while talking

        // Keep everything on the device when possible.
        if recognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        // Tap the microphone. This closure runs every time a new chunk
        // of audio arrives, and forwards it to the recognizer.
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        task = recognizer?.recognitionTask(with: request) { result, error in
            if let result {
                continuation.yield(result.bestTranscription.formattedString)
                if result.isFinal {
                    continuation.finish()
                }
            }
            if let error {
                continuation.finish(throwing: error)
            }
        }
    }

    /// Stops the microphone and finalizes the transcript.
    func stopTranscribing() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }

    /// Wraps Apple's old callback-style permission API in modern
    /// async/await so the rest of the code stays clean.
    private static func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    enum RecognizerError: LocalizedError {
        case notAuthorized

        var errorDescription: String? {
            "Microphone or speech recognition permission denied. Check System Settings, Privacy and Security."
        }
    }
}
