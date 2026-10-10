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
//  Voice selection is dynamic. Rather than hardcoding an identifier
//  and silently falling back to the robotic default when it is
//  missing, this ranks every installed English voice by quality and
//  picks the best. Download a better voice in System Settings and
//  Beth uses it on next launch with no code change.
//
//  Call SpeechSynthesizer.logAvailableVoices() to see what is
//  actually installed.
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

        // A slightly measured pace sounds more like an assistant.
        // Rate runs 0.0 (comically slow) to 1.0 (auctioneer).
        utterance.rate = 0.48

        utterance.voice = Self.bestVoice()

        synthesizer.speak(utterance)
    }

    /// Picks the best English voice actually installed on this Mac.
    ///
    /// WHY THIS IS NOT HARDCODED ANY MORE: the previous version asked
    /// for a specific identifier (an enhanced Evan voice) and silently
    /// fell back to the robotic default when it was not present, which
    /// is exactly what happened. Naming one voice makes the good case
    /// rare and the bad case invisible.
    ///
    /// Instead: rank every installed English voice by quality and take
    /// the best one. If the user later downloads a better voice, Beth
    /// upgrades on next launch with no code change.
    ///
    /// Quality tiers, worst to best:
    ///   .default  - the 1990s-sounding compact voices
    ///   .enhanced - noticeably better, a separate download
    ///   .premium  - best available, also a separate download
    ///
    /// Set `preferredVoiceName` to pin a specific one by name.
    static var preferredVoiceName: String? = "Samantha"

    private static func bestVoice() -> AVSpeechSynthesisVoice? {
        let english = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }

        guard !english.isEmpty else { return nil }

        func rank(_ voice: AVSpeechSynthesisVoice) -> Int {
            switch voice.quality {
            case .premium: return 3
            case .enhanced: return 2
            default: return 1
            }
        }

        // If a name is pinned and installed, take its best-quality
        // variant. Samantha ships in default, enhanced, and premium
        // flavours, and they are separate entries in this list.
        if let preferredVoiceName {
            let named = english.filter { $0.name.localizedCaseInsensitiveContains(preferredVoiceName) }
            if let best = named.max(by: { rank($0) < rank($1) }) {
                return best
            }
        }

        // Otherwise the highest-quality English voice installed,
        // preferring en-US on ties.
        return english.max { a, b in
            if rank(a) != rank(b) { return rank(a) < rank(b) }
            let aUS = a.language == "en-US" ? 1 : 0
            let bUS = b.language == "en-US" ? 1 : 0
            return aUS < bUS
        }
    }

    /// Prints every installed voice with its quality tier.
    ///
    /// Call this once from the app and read the console when you want
    /// to know what is actually available, rather than guessing at
    /// identifiers. Voices that are not downloaded do not appear here
    /// at all, which is the usual reason a hardcoded identifier fails.
    static func logAvailableVoices() {
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { $0.name < $1.name }

        print("Installed English voices (\(voices.count)):")
        for voice in voices {
            let quality: String
            switch voice.quality {
            case .premium: quality = "premium"
            case .enhanced: quality = "enhanced"
            default: quality = "default"
            }
            print("  \(voice.name)  [\(voice.language)]  \(quality)  \(voice.identifier)")
        }
    }

    /// Immediately stops any speech in progress.
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}
