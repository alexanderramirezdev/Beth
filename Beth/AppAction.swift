//
//  AppAction.swift
//  Beth
//
//  THE SCHEMA, v4: the field is removed again.
//
//  WHY WE ARE UNDOING v3
//
//  v3 added objectIsIdentifiable, a mandatory judgment emitted before
//  intent, to test whether STRUCTURE could enforce a rule that PROSE
//  could not. Three trials per case gave a clear answer.
//
//  It did not fix the referent problem. Referent stayed at 12 percent.
//  And it cut object extraction roughly in half, 69 percent down to 29.
//
//  The mechanism was visible in the data. Across 96 trials the model
//  answered true only 11 times, and object extraction tracked that
//  judgment almost perfectly:
//
//      identifiable true   ->  object correct 11 of 11
//      identifiable false  ->  object correct  3 of 37
//
//  The model declared plain nouns unidentifiable, then honored its own
//  declaration by leaving the object field empty. "I need to pick up
//  some bread" returned nothing.
//
//  THE INTERESTING PART: field ordering propagated to `object` and
//  suppressed it, but did NOT propagate to `intent`, even though the
//  @Guide on intent explicitly said it must be unknown when the field
//  was false. A preceding field influenced a free-text field and not
//  an enum field, in the same struct, in the same generation. That
//  asymmetry is worth its own experiment.
//
//  This file is v2's schema exactly. Run it at 3 trials. If object
//  returns to roughly 69 percent, the field caused the drop and you
//  have a controlled before/after/before with repeated measurements,
//  which is a real result rather than an anecdote.
//

import Foundation
import FoundationModels

/// The set of things our imaginary app knows how to do.
///
/// `unknown` is a first-class option on purpose. A system that cannot
/// say "I do not know" will confidently do the wrong thing instead.
@Generable
enum ActionIntent: String, CaseIterable {
    case addItem
    case removeItem
    case setReminder
    case sendMessage
    case playMusic
    case adjustSetting
    case search
    case unknown
}

/// One parsed command, ready for an app to execute.
@Generable
struct AppAction {

    @Guide(description: """
    The single action the user wants performed. Choose unknown if the \
    request does not clearly identify both an action and what it applies to.
    """)
    let intent: ActionIntent

    @Guide(description: """
    The specific thing being acted upon, and nothing else. Examples: \
    for "add milk to my shopping list" the object is "milk", not the list. \
    For "remove eggs from the list" the object is "eggs". For "text Sarah" \
    the object is "Sarah". For "turn up the brightness" the object is \
    "brightness". Never put a list name, app name, or destination here. \
    Use an empty string if the request does not name a specific thing.
    """)
    let object: String

    @Guide(description: """
    The list, place, or destination the object goes into or comes out of. \
    Examples: for "add milk to my shopping list" the container is \
    "shopping list". For "remove eggs from the list" it is "list". \
    Most requests have no container. Use an empty string when there is none.
    """)
    let container: String

    @Guide(description: """
    Any remaining detail such as a time, a quantity, a level, or the body \
    of a message. Examples: "3pm", "two dozen", "up", "I am running late". \
    Use an empty string if there is none.
    """)
    let value: String

    @Guide(description: """
    How confident you are that this interpretation is correct, from 0.0 \
    for a pure guess to 1.0 for completely certain.
    """)
    let confidence: Double
}

// MARK: - Display helpers

extension AppAction {
    /// A compact one-line rendering, useful in lists and logs.
    var summary: String {
        var parts = [intent.rawValue]
        if !object.isEmpty { parts.append("object: \(object)") }
        if !container.isEmpty { parts.append("in: \(container)") }
        if !value.isEmpty { parts.append("value: \(value)") }
        return parts.joined(separator: "  |  ")
    }
}
