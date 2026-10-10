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

        /// Separate from `rejection` on purpose. Signature rules and
        /// grounding catch different things and are measured apart so
        /// their contributions can be told from one another.
        let groundingRejection: ActionValidator.GroundingRejection?

        /// What the app would act on under a given validator mode.
        func effectiveIntent(mode: ValidatorMode) -> ActionIntent? {
            guard let action else { return nil }
            switch mode {
            case .off:
                return action.intent
            case .signatureRules:
                return rejection != nil ? .unknown : action.intent
            case .grounding:
                return groundingRejection != nil ? .unknown : action.intent
            case .both:
                return (rejection != nil || groundingRejection != nil)
                    ? .unknown : action.intent
            }
        }

        func isCorrect(mode: ValidatorMode) -> Bool {
            effectiveIntent(mode: mode) == testCase.expected
        }

        // Kept so existing call sites continue to compile.
        func effectiveIntent(validated: Bool) -> ActionIntent? {
            effectiveIntent(mode: validated ? .both : .off)
        }

        func isCorrect(validated: Bool) -> Bool {
            isCorrect(mode: validated ? .both : .off)
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

    /// Which checks are applied when scoring.
    ///
    /// Stored generations are scored under each mode without rerunning,
    /// so the four columns are the SAME samples measured four ways.
    /// Any difference between them is the check, not sampling noise.
    enum ValidatorMode: String, CaseIterable, Identifiable {
        case off = "Off"
        case signatureRules = "Rules"
        case grounding = "Grounding"
        case both = "Both"

        var id: String { rawValue }
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

    /// Captured at the start of every run and written into the CSV.
    /// See RunEnvironment for why this is not optional bookkeeping.
    var environment: RunEnvironment?
    var baseline: Baseline?

    /// Toggling this recomputes every metric instantly. No rerun needed.
    var validationEnabled = true

    var trialsPerCase = 3
    var includedDifficulties: Set<TestCase.Difficulty> = Set(TestCase.Difficulty.allCases)

    /// Which benchmark to run.
    ///
    /// Dev set is TestSuite: the validator rules were derived by
    /// reading its failures, so scores on it are optimistic by
    /// construction.
    ///
    /// Held-out was written before Rule 3 existed and run only after.
    /// It is the honest measurement of whether Rule 3 generalizes.
    enum Suite: String, CaseIterable, Identifiable {
        case development = "Dev set"
        case heldOut = "Held-out"

        var id: String { rawValue }

        var cases: [TestCase] {
            switch self {
            case .development: return TestSuite.all
            case .heldOut: return HeldOutSuite.all
            }
        }
    }

    var suite: Suite = .development

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
        accuracy(mode: .off)
    }

    /// Accuracy under any single mode, computed from stored generations.
    /// No rerun: the four modes score identical samples.
    func accuracy(mode: ValidatorMode) -> Double {
        guard !outcomes.isEmpty else { return 0 }
        return Double(outcomes.filter { $0.isCorrect(mode: mode) }.count)
            / Double(outcomes.count)
    }

    /// How many trials each check rejected, and what those rejections
    /// did to correctness. A check that rejects a wrong answer helps; a
    /// check that rejects a right answer is a false alarm.
    struct CheckReport {
        let rejected: Int
        let fixed: Int
        let broken: Int

        var precision: Double? {
            rejected == 0 ? nil : Double(fixed) / Double(rejected)
        }
    }

    func report(for mode: ValidatorMode) -> CheckReport {
        let rejects: (Outcome) -> Bool
        switch mode {
        case .off:
            return CheckReport(rejected: 0, fixed: 0, broken: 0)
        case .signatureRules:
            rejects = { $0.rejection != nil }
        case .grounding:
            rejects = { $0.groundingRejection != nil }
        case .both:
            rejects = { $0.rejection != nil || $0.groundingRejection != nil }
        }

        let rejected = outcomes.filter(rejects)
        return CheckReport(
            rejected: rejected.count,
            fixed: rejected.filter { !$0.isCorrect(mode: .off) && $0.isCorrect(mode: mode) }.count,
            broken: rejected.filter { $0.isCorrect(mode: .off) && !$0.isCorrect(mode: mode) }.count
        )
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

    /// Stability of the OBJECT field, not just intent.
    ///
    /// Finding 5d: intent was 100% stable while extraction still
    /// flipped on individual cases. "Remove eggs from the list"
    /// produced `eggs` on trials 1 and 3 and an empty object on
    /// trial 2. Intent-only stability OVERSTATES reliability, so
    /// both numbers get reported.
    var objectStability: Double {
        let summaries = caseSummaries
        guard !summaries.isEmpty else { return 0 }
        let stable = summaries.filter { summary in
            let objects = summary.trials.compactMap { $0.action?.object }
            guard let first = objects.first else { return true }
            return objects.allSatisfy { $0 == first }
        }
        return Double(stable.count) / Double(summaries.count)
    }

    /// Confidence values outside the documented 0.0 to 1.0 range.
    /// Finding 5c: the model emitted 100.0 here. Constrained decoding
    /// guarantees the type, not the range.
    var outOfRangeConfidenceCount: Int {
        outcomes.compactMap(\.action?.confidence).filter { $0 < 0 || $0 > 1 }.count
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

        let cases = suite.cases.filter { includedDifficulties.contains($0.difficulty) }
        guard !cases.isEmpty else { return }

        isRunning = true
        outcomes.removeAll()

        let trials = max(trialsPerCase, 1)

        Task {
            environment = RunEnvironment.capture()
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
                                                             sentence: testCase.sentence),
                            groundingRejection: ActionValidator.groundingRejection(
                                for: result.action, sentence: testCase.sentence)
                        ))
                    } catch {
                        outcomes.append(Outcome(
                            caseID: testCase.id,
                            trial: trial,
                            testCase: testCase,
                            action: nil,
                            seconds: 0,
                            errorText: error.localizedDescription,
                            rejection: nil,
                            groundingRejection: nil
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
        let env = environment
        var lines: [String] = []

        // Provenance header. Without it a CSV cannot be compared to
        // any other CSV, because the model underneath is not stable.
        if let env {
            lines.append("# suite=\(suite.rawValue) trials=\(trialsPerCase) os=\(env.osVersion) build=\(env.osBuild) run=\(ISO8601DateFormatter().string(from: env.timestamp))")
        }

        lines.append("sentence,difficulty,trial,expected,raw_predicted,validated_predicted,rejected,reason,grounded,grounding_reason,correct_off,correct_rules,correct_grounding,correct_both,object,object_correct,confidence,seconds,os_build")
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
            let grounded = outcome.groundingRejection == nil
            let groundingReason = outcome.groundingRejection?.rawValue
                .replacingOccurrences(of: ",", with: ";") ?? ""
            lines.append("\(sentence),\(outcome.testCase.difficulty.rawValue),\(outcome.trial),\(outcome.testCase.expected.rawValue),\(raw),\(validated),\(rejected),\(reason),\(grounded),\(groundingReason),\(outcome.isCorrect(mode: .off)),\(outcome.isCorrect(mode: .signatureRules)),\(outcome.isCorrect(mode: .grounding)),\(outcome.isCorrect(mode: .both)),\(object),\(objectCorrect),\(confidence),\(seconds),\(env?.osBuild ?? "unknown")")
        }
        return lines.joined(separator: "\n")
    }
}
