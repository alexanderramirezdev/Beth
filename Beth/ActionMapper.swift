//
//  ActionMapper.swift
//  Beth
//
//  THE MAPPER, v2. Sentence in, typed AppAction out, with a stopwatch.
//
//  Three design choices here are methodological, not stylistic.
//
//  1. FRESH SESSION PER REQUEST. The chat app reuses one session so the
//     model remembers context. Here we deliberately do not. If case 7
//     can see cases 1 through 6, case 7 is not an independent
//     measurement and your accuracy is contaminated by ordering effects.
//
//  2. WARMUP BEFORE MEASURING. The v1 run showed 2.74s on the first
//     call and roughly 0.85s on every call after: a 3x cold start
//     penalty for loading the model into memory. That first number is
//     real, but it is a DIFFERENT quantity from steady-state latency,
//     and averaging them together produces a number that describes
//     neither. So we burn one throwaway request before the clock starts
//     and report the two separately.
//
//  3. WE MEASURE LATENCY AT ALL. Speed is half the argument for going
//     on-device. Accuracy without latency tells the half of the story
//     that makes small models look worst.
//

import Foundation
import FoundationModels

@MainActor
final class ActionMapper {

    /// The standing orders that shape every mapping request.
    ///
    /// This string is your main tuning surface. Change a sentence,
    /// rerun the suite, record the delta. Keep that log.
    var instructions = """
    You convert a user's spoken request into a single structured app action.
    Consider only the sentence given to you. Do not invent details that \
    were not said. If the request refers to something you cannot identify \
    from the sentence alone, such as "it", "that", or "the last one", use \
    the unknown intent and a low confidence rather than guessing what was \
    meant. A clear verb is not enough on its own; you must also be able to \
    identify what the verb applies to.
    """

    /// One mapping result, including how long it took.
    struct Result {
        let action: AppAction
        let seconds: Double
    }

    /// Runs one throwaway request so model load time does not land in
    /// the first measured case. Returns how long the cold start took,
    /// which is worth reporting on its own.
    @discardableResult
    func warmUp() async -> Double {
        let clock = ContinuousClock()
        let start = clock.now
        let session = LanguageModelSession(instructions: instructions)
        _ = try? await session.respond(to: "Add milk to the list",
                                       generating: AppAction.self)
        return Self.seconds(from: start, clock: clock)
    }

    /// Map a single sentence to a structured action.
    ///
    /// NOTE ON API DRIFT: if Xcode complains about `.content` below,
    /// delete that one accessor.
    func map(_ sentence: String) async throws -> Result {
        // A brand new session every time. See note 1 above.
        let session = LanguageModelSession(instructions: instructions)

        let clock = ContinuousClock()
        let start = clock.now

        let response = try await session.respond(
            to: sentence,
            generating: AppAction.self
        )

        return Result(
            action: response.content,
            seconds: Self.seconds(from: start, clock: clock)
        )
    }

    private static func seconds(
        from start: ContinuousClock.Instant,
        clock: ContinuousClock
    ) -> Double {
        let elapsed = start.duration(to: clock.now)
        return Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18
    }
}
