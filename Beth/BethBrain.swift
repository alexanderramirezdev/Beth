//
//  BethBrain.swift
//  Beth
//
//  THE MIND.
//
//  This version uses ONLY the original 2025 Foundation Models API,
//  the one that shipped with macOS 26 / iOS 26. No third-party
//  packages, no LanguageModel protocol, no server-side models.
//
//  What that means practically:
//    - One engine: Apple's on-device model
//    - Free, private, offline, no entitlement, no key
//    - Works on the Mac you actually have today
//
//  What you give up until you upgrade to macOS 27:
//    - Swapping in Claude or Gemini through the same session API
//    - Private Cloud Compute
//    - MLXLanguageModel for Hugging Face models
//
//  All of that is OS 27 territory. The code you already wrote for it
//  is not wasted, it is just early.
//

import Foundation
import FoundationModels

@MainActor
final class BethBrain {

    // MARK: - Configuration

    /// Beth's standing orders. This string is her entire personality
    /// and most of her judgment.
    ///
    /// THE LESSON WORTH KEEPING: asked about weather with no city, the
    /// model answered for New York. With nothing to go on it fell back
    /// to the most statistically likely answer in its training data.
    /// It does not know where you are, what time it is, or who you
    /// are. Every one of those gaps gets filled by you, either here as
    /// static context or by a Tool that goes and looks it up.
    ///
    /// The instructions below deliberately tell her to ASK rather than
    /// assume. A wrong answer delivered confidently is worse than a
    /// question, and this model has already demonstrated it will do
    /// exactly that if you leave it room.
    private let instructions = """
    You are Beth, a Basic Everyday Task Helper. You are calm, dry, and \
    unhurried. Be concise and precise. Prefer short paragraphs. Your \
    replies may be read aloud, so avoid markdown formatting, bullet \
    lists, and code blocks unless specifically asked. \
    You have tools available for information you do not carry yourself, \
    such as the current date and time and live weather. Use them rather \
    than guessing or saying you cannot know. \
    You do not know the user's name, location, or any personal details \
    unless they tell you in this conversation. Never assume or invent \
    them. If a request depends on their location and they have not said \
    where they are, ask before answering. \
    You are a small model running on this device. You do not carry \
    broad world knowledge. When something is outside what you know and \
    no tool covers it, say so plainly instead of guessing.
    """

    /// Tools the model can call when it needs something it does not have.
    ///
    /// This is how a model with no clock and no network answers "what is
    /// the weather tomorrow." It does not know. It knows to ASK, and
    /// these structs go and find out. Add more and its reach grows
    /// without the model changing at all.
    private let tools: [any Tool] = [
        LocationTool(),
        WeatherTool(),
        DateTimeTool()
    ]

    /// The live conversation with the model. Created on first use.
    /// The session remembers earlier turns, so follow-up questions
    /// like "what about tomorrow" work naturally.
    private lazy var session = LanguageModelSession(
        tools: tools,
        instructions: instructions
    )

    /// Label shown under each answer. Only one engine here, but the
    /// UI still expects a name, and keeping the shape identical means
    /// nothing else has to change when more engines come back.
    private(set) var lastEngine: Engine?

    enum Engine: String {
        case onDevice = "On-device"
    }

    // MARK: - Availability

    var isOnDeviceAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability {
            return true
        }
        return false
    }

    var statusLine: String {
        switch SystemLanguageModel.default.availability {
        case .available:
            return "On-device model ready. Free, private, offline."
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "This Mac cannot run the on-device model."
            case .appleIntelligenceNotEnabled:
                return "Apple Intelligence is off. Enable it in System Settings."
            case .modelNotReady:
                return "Model still downloading. Check System Settings, then retry."
            @unknown default:
                return "On-device model unavailable."
            }
        @unknown default:
            return "Model status unknown."
        }
    }

    // MARK: - Asking

    /// Ask a question and receive the answer as a growing stream of text.
    ///
    /// NOTE ON API DRIFT: on this SDK each streamed element is a
    /// snapshot wrapper, so we read `.content`. Some builds hand back a
    /// String directly, in which case drop the accessor.
    func streamAnswer(to question: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                do {
                    lastEngine = .onDevice
                    let stream = session.streamResponse(to: question)

                    // Each partial is a cumulative snapshot of the
                    // answer so far, not just the newest fragment.
                    for try await snapshot in stream {
                        continuation.yield(snapshot.content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// One-shot version, used by the Siri App Intent.
    func answer(to question: String) async throws -> String {
        lastEngine = .onDevice
        let response = try await session.respond(to: question)
        return response.content
    }

    /// Throws away the conversation memory and starts clean.
    func resetSession() {
        session = LanguageModelSession(tools: tools, instructions: instructions)
        lastEngine = nil
    }
}
