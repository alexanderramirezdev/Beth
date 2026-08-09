//
//  BethViewModel.swift
//  Beth
//
//  THE COORDINATOR.
//
//  The middleman between the UI and the services:
//    1. SpeechRecognizer  -> your voice becomes text
//    2. BethBrain       -> text goes to a model, answer comes back
//    3. SpeechSynthesizer -> the answer is spoken out loud
//
//  The UI only ever talks to THIS file. It never touches the
//  microphone or a model directly.
//

import Foundation
import Observation

// One message bubble in the conversation.
struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: Role
    var text: String
    var engine: String?   // which model answered, shown under the bubble

    enum Role {
        case user
        case jarvis
    }
}

@Observable
@MainActor
final class BethViewModel {

    // MARK: - State the UI reads

    var messages: [ChatMessage] = []
    var isListening = false
    var isThinking = false
    var liveTranscript = ""
    var statusMessage = "Click the mic and ask me anything."
    var voiceRepliesEnabled = true

    var statusLine: String { brain.statusLine }
    var isOnDeviceAvailable: Bool { brain.isOnDeviceAvailable }

    // MARK: - The three services

    private let recognizer = SpeechRecognizer()
    private let brain = BethBrain()
    private let synthesizer = SpeechSynthesizer()

    // MARK: - Actions

    func toggleListening() {
        if isListening {
            stopListeningAndAsk()
        } else {
            startListening()
        }
    }

    private func startListening() {
        // Stop any speech playing so the mic does not hear it.
        synthesizer.stop()
        liveTranscript = ""
        statusMessage = "Listening..."
        isListening = true

        Task {
            do {
                for try await partialText in recognizer.startTranscribing() {
                    liveTranscript = partialText
                }
            } catch {
                statusMessage = "Mic error: \(error.localizedDescription)"
                isListening = false
            }
        }
    }

    private func stopListeningAndAsk() {
        recognizer.stopTranscribing()
        isListening = false

        let question = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        liveTranscript = ""

        guard !question.isEmpty else {
            statusMessage = "I did not catch that. Try again."
            return
        }
        ask(question)
    }

    /// Also used for typed questions.
    func ask(_ question: String) {
        messages.append(ChatMessage(role: .user, text: question))
        isThinking = true
        statusMessage = "Thinking..."

        // Add an empty Beth bubble now, fill it in as text streams.
        var reply = ChatMessage(role: .jarvis, text: "")
        messages.append(reply)

        Task {
            do {
                for try await partial in brain.streamAnswer(to: question) {
                    reply.text = partial
                    reply.engine = brain.lastEngine?.rawValue
                    if let index = messages.lastIndex(where: { $0.id == reply.id }) {
                        messages[index] = reply
                    }
                }

                isThinking = false
                statusMessage = "Click the mic and ask me anything."

                if voiceRepliesEnabled {
                    synthesizer.speak(reply.text)
                }
            } catch {
                isThinking = false
                let message = "Error: \(error.localizedDescription)"
                statusMessage = message
                if let index = messages.lastIndex(where: { $0.id == reply.id }) {
                    messages[index].text = message
                }
            }
        }
    }

    /// Wipes the conversation and every model's short-term memory.
    func clearConversation() {
        messages.removeAll()
        brain.resetSession()
        statusMessage = "Fresh start. Ask me anything."
    }
}
