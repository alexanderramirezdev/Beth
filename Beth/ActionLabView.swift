//
//  ActionLabView.swift
//  Beth
//
//  THE LAB, v5.
//
//  The validator toggle recomputes everything instantly against the
//  same stored generations, so flipping it is a controlled comparison
//  on identical samples rather than a fresh run.
//

import SwiftUI

struct ActionLabView: View {

    @State private var viewModel = ActionLabViewModel()
    @State private var copiedCSV = false

    var body: some View {
        VStack(spacing: 0) {
            scratchPad
            Divider()
            controls
            Divider()
            resultsList
        }
    }

    // MARK: - Scratch pad

    private var scratchPad: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try a sentence")
                .font(.headline)

            HStack {
                TextField("Add milk to my shopping list", text: $viewModel.scratchSentence)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { viewModel.runScratch() }

                Button("Map") { viewModel.runScratch() }
                    .disabled(viewModel.isRunning)
            }

            if !viewModel.scratchResult.isEmpty {
                Text(viewModel.scratchResult)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
    }

    // MARK: - Controls

    private var controls: some View {
        @Bindable var viewModel = viewModel

        return VStack(spacing: 12) {
            HStack {
                ForEach(TestCase.Difficulty.allCases, id: \.self) { difficulty in
                    Toggle(difficulty.rawValue, isOn: Binding(
                        get: { viewModel.includedDifficulties.contains(difficulty) },
                        set: { isOn in
                            if isOn {
                                viewModel.includedDifficulties.insert(difficulty)
                            } else {
                                viewModel.includedDifficulties.remove(difficulty)
                            }
                        }
                    ))
                    .toggleStyle(.checkbox)
                }

                Spacer()

                Picker("Trials", selection: $viewModel.trialsPerCase) {
                    Text("1").tag(1)
                    Text("3").tag(3)
                    Text("5").tag(5)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)

                if viewModel.isRunning {
                    ProgressView().controlSize(.small)
                }

                Button("Run suite") { viewModel.runSuite() }
                    .disabled(viewModel.isRunning || viewModel.includedDifficulties.isEmpty)
            }

            HStack {
                Toggle("Validator", isOn: $viewModel.validationEnabled)
                    .toggleStyle(.switch)
                    .help("Recomputes instantly against the same generations")

                if !viewModel.outcomes.isEmpty {
                    Text(String(format: "raw %.0f%% -> validated %.0f%%",
                                viewModel.intentAccuracyRaw * 100,
                                viewModel.intentAccuracy * 100))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(viewModel.progressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !viewModel.outcomes.isEmpty {
                scoreboard
            }
        }
        .padding()
    }

    private var scoreboard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 18) {
                metric("Intent", percent(viewModel.intentAccuracy),
                       delta: viewModel.baseline.map { viewModel.intentAccuracy - $0.intent })
                if let object = viewModel.objectAccuracy {
                    metric("Object", percent(object),
                           delta: viewModel.baseline?.object.map { object - $0 })
                }
                metric("Stability", percent(viewModel.stability),
                       delta: viewModel.baseline.map { viewModel.stability - $0.stability })
                metric("Spread", viewModel.accuracySpread)
                metric("Median", String(format: "%.2fs", viewModel.medianSeconds))
                if let cold = viewModel.coldStartSeconds {
                    metric("Cold start", String(format: "%.1fs", cold))
                }
            }

            HStack(spacing: 16) {
                ForEach(TestCase.Difficulty.allCases, id: \.self) { difficulty in
                    if let accuracy = viewModel.accuracy(for: difficulty) {
                        Text("\(difficulty.rawValue) \(percent(accuracy))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            // How the validator itself performed.
            if viewModel.rejectionCount > 0 {
                HStack(spacing: 14) {
                    Text("Validator")
                        .font(.caption.bold())
                    Text("\(viewModel.rejectionCount) rejected")
                    Text("\(viewModel.rejectionsCaught) fixed")
                        .foregroundStyle(.green)
                    Text("\(viewModel.rejectionsFalseAlarm) broken")
                        .foregroundStyle(viewModel.rejectionsFalseAlarm > 0 ? .orange : .secondary)
                    if let precision = viewModel.validatorPrecision {
                        Text("precision \(percent(precision))")
                    }
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Set baseline") {
                    viewModel.snapshotBaseline(label: "previous run")
                }
                .font(.caption)

                Button(copiedCSV ? "Copied" : "Copy CSV") {
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(viewModel.exportCSV(), forType: .string)
                    #endif
                    copiedCSV = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copiedCSV = false
                    }
                }
                .font(.caption)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func metric(_ label: String, _ value: String, delta: Double? = nil) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.bold().monospacedDigit())
            HStack(spacing: 3) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let delta, abs(delta) > 0.001 {
                    Text(String(format: "%+.0f", delta * 100))
                        .font(.caption2.bold())
                        .foregroundStyle(delta > 0 ? Color.green : Color.red)
                }
            }
        }
    }

    // MARK: - Results

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(viewModel.caseSummaries) { summary in
                    row(for: summary)
                }
            }
            .padding()
        }
    }

    private func row(for summary: ActionLabViewModel.CaseSummary) -> some View {
        let total = summary.trials.count
        let correct = summary.correctCount

        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: correct == total ? "checkmark.circle.fill"
                  : correct == 0 ? "xmark.circle.fill"
                  : "exclamationmark.triangle.fill")
                .foregroundStyle(correct == total ? Color.green
                                 : correct == 0 ? Color.red : Color.orange)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(summary.testCase.sentence)
                        .font(.callout)

                    if !summary.isStable {
                        Text("UNSTABLE")
                            .font(.caption2.bold())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.25),
                                        in: RoundedRectangle(cornerRadius: 4))
                    }
                }

                ForEach(summary.trials) { trial in
                    HStack(spacing: 6) {
                        Text("\(trial.trial).")
                            .foregroundStyle(.tertiary)
                        Text(trial.action?.summary ?? (trial.errorText ?? "error"))
                            .foregroundStyle(
                                trial.isCorrect(validated: summary.validated)
                                ? .secondary : Color.orange
                            )
                        if let rejection = trial.rejection, summary.validated {
                            Text("-> unknown (\(rejection.rawValue))")
                                .foregroundStyle(.blue)
                        }
                    }
                    .font(.system(.caption2, design: .monospaced))
                }

                HStack(spacing: 10) {
                    Text("\(correct) of \(total) correct")
                    Text("expected \(summary.testCase.expected.rawValue)")
                    Text(summary.testCase.difficulty.rawValue)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(10)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Helpers

    private func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }
}

#Preview {
    ActionLabView()
        .frame(width: 800, height: 900)
}
