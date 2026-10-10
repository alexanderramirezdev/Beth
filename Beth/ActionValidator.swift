//
//  ActionValidator.swift
//  Beth
//
//  THE VALIDATOR.
//
//  WHY THIS EXISTS
//
//  Four experiments established that the model cannot flag unresolved
//  referents:
//
//    v2  prose instruction listing "it", "that", "the last one"
//        by name              -> Referent 12%
//    v3  mandatory self-assessment field emitted before intent
//                             -> Referent 12%, and object extraction
//                                collapsed from 92% to 29%
//    v4  field removed        -> Referent 12%
//
//  The v4 data showed why. On the failing cases the model put the
//  pronoun itself into the object slot:
//
//      "Remove those"      -> object: "those"
//      "Send it to her"    -> object: "her"
//      "Put that on there" -> object: "that"
//      "Add it"            -> object: "it"
//
//  It is not failing to notice that the referent is unresolved. It does
//  not distinguish a referring expression from a referent at all. From
//  its point of view the object field is filled, so there is nothing to
//  report. You cannot ask a system to flag a distinction it does not make.
//
//  THE FIX IS NOT A MODEL FIX
//
//  A referring expression is a closed class of words. Detecting one is
//  string matching, not inference. So we check the model's output with
//  ordinary code: zero latency, zero cost, perfectly deterministic, and
//  it does exactly the same thing every single time, which is more than
//  the model can say.
//
//  The general claim, which your data supports across four versions:
//  for small on-device models, validate the output externally rather
//  than asking the model to assess itself.
//

import Foundation

struct ActionValidator {

    /// Words that refer to something without naming it. This is a closed
    /// class in English, which is exactly why code can handle it.
    static let referringExpressions: Set<String> = [
        "it", "its", "that", "this", "those", "these", "them", "they",
        "one", "ones", "there", "here", "him", "her", "his", "hers",
        "he", "she", "the last one", "that one", "this one",
        "the other one", "the first one", "the same", "the usual"
    ]

    /// Intents that are meaningless without knowing what they act on.
    ///
    /// setReminder, adjustSetting, and playMusic are deliberately absent.
    /// "Set a reminder for 3pm", "Turn up the volume", and "Put on
    /// something upbeat" are all complete requests with an empty object,
    /// so requiring one would produce false rejections.
    static let intentsRequiringObject: Set<ActionIntent> = [
        .addItem, .removeItem, .sendMessage, .search
    ]

    /// Intents where an empty object is often legitimate.
    /// "Set a reminder for 3pm" and "Put on something upbeat" are
    /// complete requests with nothing to name. Rule 3 applies a
    /// narrower test to these rather than exempting them entirely.
    static let intentsAllowingEmptyObject: Set<ActionIntent> = [
        .setReminder, .adjustSetting, .playMusic
    ]

    enum Rejection: String {
        case pronounAsObject = "object is a referring expression"
        case missingRequiredObject = "intent requires an object, none given"
        case danglingReferentInSentence = "no object, and the sentence only refers"
    }

    /// Returns a rejection reason, or nil when the action looks executable.
    static func check(_ action: AppAction, sentence: String) -> Rejection? {

        let object = action.object
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        // RULE 1: the object slot holds a word that refers rather than names.
        // Catches "Remove those", "Send it to her", "Add it".
        if !object.isEmpty && referringExpressions.contains(object) {
            return .pronounAsObject
        }

        // Also catch a leading article: "the last one", "that one".
        let stripped = object
            .replacingOccurrences(of: "^(the|a|an) ", with: "",
                                  options: [.regularExpression])
        if !stripped.isEmpty && referringExpressions.contains(stripped) {
            return .pronounAsObject
        }

        // RULE 2: an intent that needs an object was given none.
        // Catches "Add it" and "Get rid of the last one" on the trials
        // where the model left the object empty instead of filling it
        // with the pronoun.
        if object.isEmpty && intentsRequiringObject.contains(action.intent) {
            return .missingRequiredObject
        }

        // RULE 3 (v2): exempt intent, empty object, and the sentence
        // itself only refers. "Play it again" has no object and no noun
        // to fall back on. "Put on something upbeat" has no object
        // either, but nothing in it points at an unnamed thing.
        //
        // CAVEAT WORTH REPEATING: this rule was derived by reading
        // failures in TestSuite. Scoring it on TestSuite would be
        // fitting to the benchmark. HeldOutSuite is the honest test.
        if object.isEmpty
            && intentsAllowingEmptyObject.contains(action.intent)
            && sentenceContainsReferringExpression(sentence) {
            return .danglingReferentInSentence
        }

        return nil
    }

    /// Whether any standalone word in the sentence refers rather than
    /// names. Word-boundary matching matters: a naive `contains` would
    /// fire on "it" inside "Italian" and reject a valid search.
    private static func sentenceContainsReferringExpression(_ sentence: String) -> Bool {
        let words = sentence
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return words.contains { referringExpressions.contains($0) }
    }

    /// The intent the app should actually act on.
    static func effectiveIntent(for action: AppAction, sentence: String) -> ActionIntent {
        check(action, sentence: sentence) == nil ? action.intent : .unknown
    }
}
