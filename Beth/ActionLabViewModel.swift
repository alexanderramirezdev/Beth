//
//  ActionLabViewModel.swift
//  Beth
//
//  THE EXPERIMENT RUNNER, v5.
//
//  New: the validator can be toggled on and off WITHOUT rerunning.
//  Raw model output is stored once; validation is applied at scoring
//  time. That means the on/off comparison uses literally the same
//  generations, so any difference is the validator and nothing else.
//  This is the tightest controlled comparison in the whole project:
//  not just the same configuration, the same samples.
//

import Foundation
import Observation

@Observable
@MainActor
final class ActionLabViewModel {

    // MARK: - One trial

    struct Outcome: Identifiable {
        let id = UUID()
        let caseID: UUID
        let trial: Int
        let testCase: TestCase
        let action: AppAction?
        let seconds: Double
        let errorText: String?

        /// Computed once at run time from the raw action.
        let rejection: ActionValidator.Rejection?

        /// What the app would act on, with or without the validator.
        func effectiveIntent(validated: Bool) -> ActionIntent? {
            guard let action else { return nil }
            if validated && rejection != nil { return .unknown }
            return action.intent
        }

        func isCorrect(validated: Bool) -> Bool {
            effectiveIntent(validated: validated) == testCase.expected
        }

        var objectCorrect: Bool? {
            guard let expected = testCase.expectedObjectContains,
                  let actual = action?.object else { return nil }
            return actual.localizedCaseInsensitiveContains(expected)
        }

        var containerCorrect: Bool? {
            guard let expected = testCase.expectedContainerContains,
                  let actual = action?.container else { return nil }
            return actual.localizedCaseInsensitiveContains(expected)
        }
    }

    struct CaseSummary: Identifiable {
        let id: UUID
        let testCase: TestCase
        let trials: [Outcome]
        let validated: Bool

        var majorityCount: Int {
            let intents = trials.compactMap { $0.effectiveIntent(validated: validated) }
            let counts = Dictionary(grouping: intents, by: { $0 }).mapValues(\.count)
            return counts.values.max() ?? 0
        }

        var isStable: Bool { majorityCount == trials.count }

        var correctCount: Int {
            trials.filter { $0.isCorrect(validated: validated) }.count
        }
    }

    struct Baseline {
        let intent: Double
        let object: Double?
        let stability: Double
        let label: String
    }

    // MARK: - State

    var outcomes: [Outcome] = []
    var isRunning = false
    var progressText = ""
    var coldStartSeconds: Double?
    var baseline: Baseline?

    /// Toggling this recomputes every metric instantly. No rerun needed.
    var validationEnabled = true

    var trialsPerCase = 3
    var includedDifficulties: Set<TestCase.Difficulty> = Set(TestCase.Difficulty.allCases)

    var scratchSentence = ""
    var scratchResult = ""

    private let mapper = ActionMapper()

    // MARK: - Grouping

    var caseSummaries: [CaseSummary] {
        let grouped = Dictionary(grouping: outcomes, by: \.caseID)
        return grouped.compactMap { key, trials -> CaseSummary? in
            guard let first = trials.first else { return nil }
            return CaseSummary(
                id: key,
                testCase: first.testCase,
                trials: trials.sorted { $0.trial < $1.trial },
                validated: validationEnabled
            )
        }
        .sorted { lhs, rhs in
            let order = TestCase.Difficulty.allCases
            let l = order.firstIndex(of: lhs.testCase.difficulty) ?? 0
            let r = order.firstIndex(of: rhs.testCase.difficulty) ?? 0
            if l != r { return l < r }
            return lhs.testCase.sentence < rhs.testCase.sentence
        }
    }

    // MARK: - Aggregate numbers

    var intentAccuracy: Double {
        guard !outcomes.isEmpty else { return 0 }
        return Double(outcomes.filter { $0.isCorrect(validated: validationEnabled) }.count)
            / Double(outcomes.count)
    }

    /// The same number with the validator forced off, for side-by-side.
    var intentAccuracyRaw: Double {
        guard !outcomes.isEmpty else { return 0 }
        return Double(outcomes.filter { $0.isCorrect(validated: false) }.count)
            / Double(outcomes.count)
    }

    var objectAccuracy: Double? {
        let scored = outcomes.compactMap(\.objectCorrect)
        guard !scored.isEmpty else { return nil }
        return Double(scored.filter { $0 }.count) / Double(scored.count)
    }

    var stability: Double {
        let summaries = caseSummaries
        guard !summaries.isEmpty else { return 0 }
        return Double(summaries.filter(\.isStable).count) / Double(summaries.count)
    }

    var trialAccuracies: [Double] {
        (1...max(trialsPerCase, 1)).compactMap { trial in
            let subset = outcomes.filter { $0.trial == trial }
            guard !subset.isEmpty else { return nil }
            return Double(subset.filter { $0.isCorrect(validated: validationEnabled) }.count)
                / Double(subset.count)
        }
    }

    var accuracySpread: String {
        let values = trialAccuracies
        guard let low = values.min(), let high = values.max(), values.count > 1 else { return "-" }
        return String(format: "%.0f to %.0f%%", low * 100, high * 100)
    }

    var medianSeconds: Double {
        let times = outcomes.map(\.seconds).sorted()
        guard !times.isEmpty else { return 0 }
        return times[times.count / 2]
    }

    func accuracy(for difficulty: TestCase.Difficulty) -> Double? {
        let subset = outcomes.filter { $0.testCase.difficulty == difficulty }
        guard !subset.isEmpty else { return nil }
        return Double(subset.filter { $0.isCorrect(validated: validationEnabled) }.count)
            / Double(subset.count)
    }

    // MARK: - Validator performance
    //
    // A validator that rejects everything would score perfectly on the
    // Referent tier and destroy the rest, so rejections have to be
    // scored in both directions.
    //
    //   caught      - rejections that turned a wrong answer into a right one
    //   falseAlarms - rejections that turned a right answer into a wrong one

    var rejectionCount: Int {
        outcomes.filter { $0.rejection != nil }.count
    }

    var rejectionsCaught: Int {
        outcomes.filter {
            $0.rejection != nil && !$0.isCorrect(validated: false) && $0.isCorrect(validated: true)
        }.count
    }

    var rejectionsFalseAlarm: Int {
        outcomes.filter {
            $0.rejection != nil && $0.isCorrect(validated: false) && !$0.isCorrect(validated: true)
        }.count
    }

    var validatorPrecision: Double? {
        guard rejectionCount > 0 else { return nil }
        return Double(rejectionsCaught) / Double(rejectionCount)
    }

    // MARK: - Running

    func snapshotBaseline(label: String) {
        guard !outcomes.isEmpty else { return }
        baseline = Baseline(
            intent: intentAccuracy,
            object: objectAccuracy,
            stability: stability,
            label: label
        )
    }

    func runSuite() {
        guard !isRunning else { return }

        let cases = TestSuite.all.filter { includedDifficulties.contains($0.difficulty) }
        guard !cases.isEmpty else { return }

        isRunning = true
        outcomes.removeAll()

        let trials = max(trialsPerCase, 1)

        Task {
            progressText = "Warming up..."
            coldStartSeconds = await mapper.warmUp()

            let total = cases.count * trials
            var done = 0

            // Trial-major order spreads any slow drift in machine state
            // evenly across cases instead of concentrating it.
            for trial in 1...trials {
                for testCase in cases {
                    done += 1
                    progressText = "Trial \(trial) of \(trials)  |  \(done) of \(total)"

                    do {
                        let result = try await mapper.map(testCase.sentence)
                        outcomes.append(Outcome(
                            caseID: testCase.id,
                            trial: trial,
                            testCase: testCase,
                            action: result.action,
                            seconds: result.seconds,
                            errorText: nil,
                            rejection: ActionValidator.check(result.action,
                                                             sentence: testCase.sentence)
                        ))
                    } catch {
                        outcomes.append(Outcome(
                            caseID: testCase.id,
                            trial: trial,
                            testCase: testCase,
                            action: nil,
                            seconds: 0,
                            errorText: error.localizedDescription,
                            rejection: nil
                        ))
                    }
                }
            }

            progressText = "Done. \(cases.count) cases x \(trials) trials."
            isRunning = false
        }
    }

    func runScratch() {
        let sentence = scratchSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty, !isRunning else { return }

        isRunning = true
        scratchResult = "Thinking..."

        Task {
            do {
                let result = try await mapper.map(sentence)
                let rejection = ActionValidator.check(result.action, sentence: sentence)
                var text = result.action.summary
                if let rejection {
                    text += "\nREJECTED: \(rejection.rawValue)  ->  unknown"
                }
                text += String(format: "\nconfidence %.2f  |  %.2fs",
                               result.action.confidence, result.seconds)
                scratchResult = text
            } catch {
                scratchResult = "Error: \(error.localizedDescription)"
            }
            isRunning = false
        }
    }

    func exportCSV() -> String {
        var lines = ["sentence,difficulty,trial,expected,raw_predicted,validated_predicted,rejected,reason,raw_correct,validated_correct,object,object_correct,confidence,seconds"]
        for outcome in outcomes.sorted(by: { $0.testCase.sentence < $1.testCase.sentence }) {
            let sentence = outcome.testCase.sentence.replacingOccurrences(of: ",", with: ";")
            let raw = outcome.action?.intent.rawValue ?? "ERROR"
            let validated = outcome.effectiveIntent(validated: true)?.rawValue ?? "ERROR"
            let rejected = outcome.rejection != nil
            let reason = outcome.rejection?.rawValue.replacingOccurrences(of: ",", with: ";") ?? ""
            let object = (outcome.action?.object ?? "").replacingOccurrences(of: ",", with: ";")
            let objectCorrect = outcome.objectCorrect.map(String.init) ?? ""
            let confidence = outcome.action.map { String(format: "%.2f", $0.confidence) } ?? ""
            let seconds = String(format: "%.3f", outcome.seconds)
            lines.append("\(sentence),\(outcome.testCase.difficulty.rawValue),\(outcome.trial),\(outcome.testCase.expected.rawValue),\(raw),\(validated),\(rejected),\(reason),\(outcome.isCorrect(validated: false)),\(outcome.isCorrect(validated: true)),\(object),\(objectCorrect),\(confidence),\(seconds)")
        }
        return lines.joined(separator: "\n")
    }
}
