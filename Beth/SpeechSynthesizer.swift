//
//  SpeechSynthesizer.swift
//  Beth
//
//  THE VOICE.
//
//  This reads Beth's answers out loud using AVSpeechSynthesizer,
//  Apple's built-in text-to-speech engine. It is the simplest of our
//  three services: give it a string, it talks.
//
//  Fun experiment once it works: iterate over
//  AVSpeechSynthesisVoice.speechVoices() to list every voice
//  installed on the device, then pick one you like. Some of the
//  newer "premium" voices sound impressively natural.
//

import Foundation
import AVFoundation

final class SpeechSynthesizer {

    private let synthesizer = AVSpeechSynthesizer()

    /// Speaks the given text out loud.
    func speak(_ text: String) {
        // If it is already talking, cut it off. New answer wins.
        stop()

        let utterance = AVSpeechUtterance(string: text)

        // A slightly measured pace sounds more "assistant-like."
        // Rate goes from 0.0 (comically slow) to 1.0 (auctioneer).
        utterance.rate = 0.48

        // Use an enhanced English voice when one is installed.
        utterance.voice =
            AVSpeechSynthesisVoice(identifier: "com.apple.voice.enhanced.en-US.Evan")
            ?? AVSpeechSynthesisVoice(language: "en-US")

        synthesizer.speak(utterance)
    }

    /// Immediately stops any speech in progress.
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}
