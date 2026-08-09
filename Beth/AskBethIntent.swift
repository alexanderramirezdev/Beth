//
//  AskBethIntent.swift
//  Beth
//
//  THE SIRI CONNECTION.
//
//  App Intents is Apple's framework for exposing pieces of your app as
//  "actions" the system can trigger: Siri, Shortcuts, Spotlight, and
//  the new Siri AI all use this same doorway.
//
//  Apple formally deprecated SiriKit at WWDC 2026 with a support window
//  of roughly two to three years, so App Intents is THE path forward.
//
//  This matters for your timeline specifically. Siri AI is coming to
//  visionOS later this year, and the way it discovers what your app can
//  do is by reading your App Intents. Every intent you define here is a
//  capability the future assistant can reach. Adding more intents is
//  how this app becomes something Siri can actually operate, rather
//  than just a chat window that happens to live on your face.
//
//  Try after installing:
//     "Hey Siri, ask Beth a question"
//
//  Why not one breath ("ask Beth what a black hole is")? App Intents
//  only allows AppEntity and AppEnum types to be interpolated into
//  spoken phrases, and our question is a free-form String. So it is a
//  two-step conversation instead. That constraint, mapping open-ended
//  language onto a fixed action vocabulary, is precisely the hard
//  problem your dissertation is about.
//

import AppIntents

struct AskBethIntent: AppIntent {

    static let title: LocalizedStringResource = "Ask Beth"
    static let description = IntentDescription(
        "Ask Beth a question and hear the answer."
    )

    @Parameter(title: "Question", requestValueDialog: "What do you want to know?")
    var question: String

    static var parameterSummary: some ParameterSummary {
        Summary("Ask Beth \(\.$question)")
    }

    // Marked @MainActor because BethBrain is main-actor isolated.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let brain = BethBrain()
        let reply = try await brain.answer(to: question)

        // ProvidesDialog means Siri speaks and displays this result.
        return .result(dialog: IntentDialog(stringLiteral: reply))
    }
}

// A phrase catalog so Siri recognizes natural ways of invoking this.
struct BethShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskBethIntent(),
            phrases: [
                "Ask \(.applicationName) a question",
                "Talk to \(.applicationName)"
            ],
            shortTitle: "Ask Beth",
            systemImageName: "waveform.circle.fill"
        )
    }
}
