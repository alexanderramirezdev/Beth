//
//  GroundingCheck.swift
//  Beth
//
//  THE VALIDATOR THAT SHOULD SURVIVE A MODEL CHANGE.
//
//  WHY THIS IS DIFFERENT FROM ActionValidator
//
//  ActionValidator's rules all encode knowledge of HOW the model
//  fails. Rule 1 knows it puts pronouns in the object slot. Rule 2
//  knows it leaves the slot empty. Both were true of the macOS 27 beta
//  model and both are largely false of the 26.6.2 shipping model,
//  which fills the slot with a plausible invented noun instead:
//
//      "Add it"            -> object: "milk"
//      "The usual"         -> object: "milk"
//      "Remove those"      -> object: "eggs"
//      "Put that on there" -> object: "shopping list"
//
//  None of those words appear in those sentences. The model completed
//  the pattern from task context rather than from the input.
//
//  A grounding check asks a different question entirely:
//
//      Does this value actually appear in what the user said?
//
//  That question does not depend on the failure mode. Confabulation is
//  detectable BY DEFINITION, because the words are not there. "milk"
//  cannot be grounded in "Add it" under any model, present or future.
//
//  THE HYPOTHESIS BEING TESTED
//
//  If a grounding check catches on Model B the cases that Rules 1 and
//  2 caught on Model A, then this class of check is version-robust
//  where signature-based rules are not. That is the property any
//  downstream system needs before it can trust extraction output.
//
//  WHAT IT CANNOT DO
//
//  Grounding checks whether a value came from the input. It does not
//  check whether the value is CORRECT, whether the intent is right, or
//  whether a grounded value refers to something resolvable. "Remove
//  those" -> object "those" is perfectly grounded and still useless.
//  Grounding is a necessary condition, not a sufficient one, and it
//  composes with the referring-expression rule rather than replacing it.
//

import Foundation

struct GroundingCheck {

    enum Result {
        /// The value appears in the input, verbatim or near enough.
        case grounded
        /// The value does not appear in the input at all.
        case ungrounded(value: String)
        /// Nothing to check.
        case empty
    }

    /// Words that legitimately appear in output without appearing in
    /// input, because they name a category rather than quote the user.
    ///
    /// This list is a known weakness. Every entry is a hole a
    /// confabulation could slip through, and it was assembled by
    /// reading Model B output, which means it is fitted to Model B.
    /// Kept small and documented rather than expanded until it works.
    static let allowedAbstractions: Set<String> = [
        "unknown", "none", "n/a", ""
    ]

    /// Does `value` appear in `sentence`?
    ///
    /// Matching is deliberately generous. The goal is to catch values
    /// invented wholesale, not to punish the model for normalizing
    /// "lights" to "light" or dropping an article. A strict check would
    /// produce false alarms on legitimate extractions and we already
    /// know from section 5f what a false-alarm-prone validator costs.
    static func check(value rawValue: String, against sentence: String) -> Result {
        let value = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !value.isEmpty else { return .empty }
        if allowedAbstractions.contains(value) { return .empty }

        let haystack = normalize(sentence)
        let needle = normalize(value)

        // 1. Whole string appears.
        if haystack.contains(needle) { return .grounded }

        // 2. Every word of the value appears somewhere in the input.
        //    Handles reordering and inserted words: "do my taxes"
        //    against "Remind me to do my taxes".
        let valueWords = needle.split(separator: " ").map(String.init)
        let inputWords = Set(haystack.split(separator: " ").map(String.init))

        if !valueWords.isEmpty
            && valueWords.allSatisfy({ word in
                inputWords.contains(word) || inputWords.contains(where: { stemMatch($0, word) })
            }) {
            return .grounded
        }

        return .ungrounded(value: rawValue)
    }

    // MARK: - Matching helpers

    /// Lowercase, strip punctuation, collapse whitespace.
    private static func normalize(_ text: String) -> String {
        let stripped = text.lowercased().map { character -> Character in
            character.isLetter || character.isNumber || character.isWhitespace ? character : " "
        }
        return String(stripped)
            .split(separator: " ")
            .joined(separator: " ")
    }

    /// Crude stem comparison so "lights" matches "light" and
    /// "restaurants" matches "restaurant".
    ///
    /// Deliberately not a real stemmer. A real one is a dependency and
    /// a source of surprises; this handles the plural case that showed
    /// up repeatedly in the data and nothing else.
    private static func stemMatch(_ a: String, _ b: String) -> Bool {
        let stem: (String) -> String = { word in
            if word.count > 3 && word.hasSuffix("es") { return String(word.dropLast(2)) }
            if word.count > 2 && word.hasSuffix("s") { return String(word.dropLast()) }
            return word
        }
        return stem(a) == stem(b)
    }
}

// MARK: - Composition with the existing validator

extension ActionValidator {

    /// A rejection reason that does not depend on knowing how the
    /// model fails.
    enum GroundingRejection: String {
        case ungroundedObject = "object does not appear in the input"
    }

    /// Checks whether the extracted object came from the sentence.
    ///
    /// Run this ALONGSIDE `check(_:sentence:)`, not instead of it. The
    /// two catch different things:
    ///
    ///   grounding  catches "Add it" -> milk        (invented)
    ///   rule 1     catches "Remove those" -> those (real, unusable)
    ///
    /// Neither subsumes the other.
    static func groundingRejection(
        for action: AppAction,
        sentence: String
    ) -> GroundingRejection? {
        switch GroundingCheck.check(value: action.object, against: sentence) {
        case .ungrounded:
            return .ungroundedObject
        case .grounded, .empty:
            return nil
        }
    }
}
