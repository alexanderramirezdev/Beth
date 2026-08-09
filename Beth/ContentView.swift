//
//  ContentView.swift
//  Beth
//
//  THE FACE.
//
//  Layout, top to bottom:
//    - Title bar with voice toggle and clear button
//    - Model status line
//    - Scrolling conversation, each answer labeled with its engine
//    - Live transcript while you speak
//    - Status line
//    - Text field plus microphone button
//
//  STRUCTURE RULE worth burning into memory: `body` describes the
//  screen, so only views go inside it. Helper functions live NEXT to
//  body, further down in the struct, never inside it. If you ever see
//  "Expected declaration" plus "Extraneous } at top level" plus a pile
//  of "cannot find X in scope", that is always a brace problem: the
//  struct closed early and everything after it fell outside.
//

import SwiftUI

struct ContentView: View {

    @Environment(BethViewModel.self) private var viewModel
    @State private var typedQuestion = ""

    var body: some View {
        // @Observable models need this bridge for two-way bindings.
        @Bindable var viewModel = viewModel

        VStack(spacing: 0) {

            // MARK: Title bar
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Label("B.E.T.H.", systemImage: "waveform.circle.fill")
                        .font(.title2.bold())
                    Text("Basic Everyday Task Helper")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 2)
                }

                Spacer()

                Toggle(isOn: $viewModel.voiceRepliesEnabled) {
                    Image(systemName: viewModel.voiceRepliesEnabled
                          ? "speaker.wave.2.fill"
                          : "speaker.slash.fill")
                }
                .toggleStyle(.button)
                .help("Spoken replies on or off")

                Button {
                    viewModel.clearConversation()
                } label: {
                    Image(systemName: "trash")
                }
                .help("Clear the conversation")
            }
            .padding()

            Divider()

            // MARK: Model status
            Text(viewModel.statusLine)
                .font(.caption)
                .foregroundStyle(viewModel.isOnDeviceAvailable ? Color.secondary : Color.orange)
                .padding(.top, 10)

            // MARK: Conversation
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if viewModel.messages.isEmpty {
                            emptyState
                        }
                        ForEach(viewModel.messages) { message in
                            bubble(for: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages) {
                    if let last = viewModel.messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            // MARK: Live transcript while speaking
            if viewModel.isListening && !viewModel.liveTranscript.isEmpty {
                Text(viewModel.liveTranscript)
                    .font(.body.italic())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .transition(.opacity)
            }

            // MARK: Status line
            Text(viewModel.statusMessage)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.vertical, 6)

            // MARK: Input row
            HStack(spacing: 12) {
                TextField("Or type a question...", text: $typedQuestion)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(sendTypedQuestion)

                Button(action: sendTypedQuestion) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(typedQuestion.trimmingCharacters(in: .whitespaces).isEmpty)

                micButton
            }
            .padding()
        }
        .frame(minWidth: 460, minHeight: 560)
    }

    // MARK: - Pieces

    /// The mic button. Red and pulsing while recording.
    private var micButton: some View {
        Button {
            viewModel.toggleListening()
        } label: {
            Image(systemName: viewModel.isListening ? "mic.fill" : "mic")
                .font(.title3)
                .padding(12)
                .background(
                    Circle().fill(viewModel.isListening ? Color.red : Color.blue)
                )
                .foregroundStyle(.white)
                .symbolEffect(.pulse, isActive: viewModel.isListening)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isThinking)
    }

    /// One chat bubble, with a badge naming the engine that answered.
    private func bubble(for message: ChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.text.isEmpty ? "..." : message.text)
                    .textSelection(.enabled)
                    .padding(12)
                    .background(
                        message.role == .user
                        ? AnyShapeStyle(Color.blue.opacity(0.85))
                        : AnyShapeStyle(.regularMaterial),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                    .foregroundStyle(message.role == .user ? Color.white : Color.primary)

                if let engine = message.engine, message.role == .jarvis {
                    Label(engine, systemImage: "cpu")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 4)
                }
            }

            if message.role == .jarvis { Spacer(minLength: 60) }
        }
    }

    /// Placeholder before the first question.
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Ready when you are.")
                .font(.title3)
            Text("Click the mic and speak, or type below.\nEverything runs on this Mac.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
    }

    // MARK: - Actions
    // Helper functions live HERE, outside body.

    private func sendTypedQuestion() {
        let question = typedQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        typedQuestion = ""
        viewModel.ask(question)
    }
}

#Preview {
    ContentView()
        .environment(BethViewModel())
}
