//
//  TestSuite.swift
//  Beth
//
//  THE BENCHMARK, v2.
//
//  Changes from v1:
//    - Expectations split into object and container, matching the schema.
//    - New REFERENT tier: eight cases testing one specific hypothesis.
//
//  THE HYPOTHESIS
//
//  In the v1 run, the four intended-unknown cases split cleanly:
//
//     "Take care of that thing we talked about"  -> unknown   CORRECT
//     "Never mind"                               -> unknown   CORRECT
//     "Add it"                                   -> addItem   WRONG
//     "Get rid of the last one"                  -> removeItem WRONG
//
//  The two it got right contain no action verb. The two it failed both
//  contain a clear verb attached to a referent that cannot be resolved
//  ("it", "the last one"). That suggests the model anchors on the
//  presence of a verb and never checks whether the object actually
//  resolves to anything.
//
//  The Referent tier tests that directly: eight sentences, all with a
//  strong verb, all with a dangling referent, all of which should be
//  unknown. If accuracy on this tier is near zero while the verb-absent
//  unknowns in Hard keep passing, the hypothesis holds and you have a
//  named, characterized failure mode instead of "it sometimes guesses."
//

import Foundation

struct TestCase: Identifiable {
    let id = UUID()
    let sentence: String
    let expected: ActionIntent

    /// Optional. If set, `object` must contain this substring
    /// (case-insensitive) to count as a match.
    let expectedObjectContains: String?

    /// Optional. If set, `container` must contain this substring.
    let expectedContainerContains: String?

    let difficulty: Difficulty

    enum Difficulty: String, CaseIterable {
        case easy = "Easy"
        case medium = "Medium"
        case hard = "Hard"
        case referent = "Referent"
    }

    init(
        _ sentence: String,
        _ expected: ActionIntent,
        object: String? = nil,
        container: String? = nil,
        difficulty: Difficulty = .easy
    ) {
        self.sentence = sentence
        self.expected = expected
        self.expectedObjectContains = object
        self.expectedContainerContains = container
        self.difficulty = difficulty
    }
}

enum TestSuite {

    static let all: [TestCase] = easy + medium + hard + referent

    /// EASY: explicit verb, plain noun target.
    static let easy: [TestCase] = [
        TestCase("Add milk to my shopping list", .addItem,
                 object: "milk", container: "shopping list"),
        TestCase("Remove eggs from the list", .removeItem,
                 object: "eggs", container: "list"),
        TestCase("Set a reminder for 3pm", .setReminder),
        TestCase("Play some jazz", .playMusic, object: "jazz"),
        TestCase("Text Sarah that I am running late", .sendMessage,
                 object: "Sarah"),
        TestCase("Search for Italian restaurants", .search,
                 object: "Italian"),
        TestCase("Turn up the brightness", .adjustSetting,
                 object: "brightness"),
        TestCase("Add batteries to the list", .addItem,
                 object: "batteries", container: "list")
    ]

    /// MEDIUM: natural phrasing, indirect verbs, implied actions.
    /// This is where most real user speech lives.
    static let medium: [TestCase] = [
        TestCase("I need to pick up some bread", .addItem,
                 object: "bread", difficulty: .medium),
        TestCase("We already got the paper towels", .removeItem,
                 object: "paper towels", difficulty: .medium),
        TestCase("Do not let me forget to call mom tonight", .setReminder,
                 object: "mom", difficulty: .medium),
        TestCase("It is too loud in here", .adjustSetting,
                 object: "volume", difficulty: .medium),
        TestCase("Let Marcus know the meeting moved", .sendMessage,
                 object: "Marcus", difficulty: .medium),
        TestCase("Put on something upbeat", .playMusic,
                 difficulty: .medium),
        TestCase("What is a good sushi place nearby", .search,
                 object: "sushi", difficulty: .medium),
        TestCase("Throw some coffee on the list too", .addItem,
                 object: "coffee", container: "list", difficulty: .medium)
    ]

    /// HARD: ambiguity and requests that should be refused.
    /// The unknown cases here are all VERB-ABSENT, which is the control
    /// group for the Referent tier below.
    static let hard: [TestCase] = [
        TestCase("Take care of that thing we talked about", .unknown,
                 difficulty: .hard),
        TestCase("Never mind", .unknown, difficulty: .hard),
        TestCase("Whatever works", .unknown, difficulty: .hard),
        TestCase("The usual", .unknown, difficulty: .hard),
        TestCase("What is the capital of France", .search,
                 object: "France", difficulty: .hard),
        TestCase("Tell her I said sorry", .sendMessage, difficulty: .hard),
        TestCase("Make it warmer in here", .adjustSetting,
                 object: "temperature", difficulty: .hard),
        TestCase("Remind me when I get there", .setReminder, difficulty: .hard)
    ]

    /// REFERENT: strong verb, unresolvable object. All should be unknown.
    ///
    /// This tier exists to test one hypothesis, not to pad the score.
    /// If it scores near zero while the verb-absent unknowns in Hard
    /// keep passing, the failure mode is confirmed and named.
    static let referent: [TestCase] = [
        TestCase("Add it", .unknown, difficulty: .referent),
        TestCase("Get rid of the last one", .unknown, difficulty: .referent),
        TestCase("Delete that one", .unknown, difficulty: .referent),
        TestCase("Send it to her", .unknown, difficulty: .referent),
        TestCase("Put that on there", .unknown, difficulty: .referent),
        TestCase("Remove those", .unknown, difficulty: .referent),
        TestCase("Play it again", .unknown, difficulty: .referent),
        TestCase("Remind me about that", .unknown, difficulty: .referent)
    ]
}
