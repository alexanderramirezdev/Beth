//
//  HeldOutSuite.swift
//  Beth
//
//  THE HELD-OUT SET.
//
//  WHY THIS FILE EXISTS
//
//  After the validator run, two failures remained, and both were
//  object-exempt intents:
//
//      "Play it again"        -> playMusic    3 of 3 wrong
//      "Remind me about that" -> setReminder  2 of 3 wrong
//
//  Reading those failures suggests an obvious rule: for the exempt
//  intents, also reject when the object is empty AND the sentence
//  contains a referring expression.
//
//  THE TRAP: that rule was derived by reading failures in TestSuite.
//  Implementing it and rescoring on TestSuite would guarantee the
//  number goes up and guarantee the number means nothing. That is
//  fitting the validator to the benchmark. Do it a few times and you
//  have a system that scores 100 percent on 32 sentences and behaves
//  unpredictably on everything else.
//
//  So these cases were written BEFORE the rule was implemented, and
//  they are scored only AFTER. Whatever they score is the honest
//  number.
//
//  THE STRUCTURE
//
//  Every case here targets playMusic, setReminder, or adjustSetting,
//  the three intents exempt from the required-object rule. Half have
//  dangling referents and should be rejected. Half have legitimately
//  empty objects and MUST NOT be rejected. That balance is the point:
//  a rule that rejects everything would score perfectly on the first
//  half and destroy the second.
//
//  AUTHORSHIP NOTE, worth recording for the writeup: cases marked
//  [C] were written by Claude, which also wrote the validator. Cases
//  marked [A] were written by Alexander independently. Same-author
//  test cases and fixes are a real source of bias, and splitting
//  authorship is a cheap partial control. Report the split.
//

import Foundation

enum HeldOutSuite {

    static let all: [TestCase] = shouldReject + shouldAccept

    /// DANGLING REFERENT. All should come back unknown.
    /// A strong verb with nothing resolvable attached to it.
    static let shouldReject: [TestCase] = [
        // [C]
        TestCase("Play that one again", .unknown, difficulty: .referent),
        TestCase("Turn it down", .unknown, difficulty: .referent),
        TestCase("Remind me about those", .unknown, difficulty: .referent),
        TestCase("Set one for that", .unknown, difficulty: .referent),

        // [A]
        TestCase("Turn off", .unknown, difficulty: .referent),
        TestCase("Play it louder", .unknown, difficulty: .referent),
        TestCase("Next song", .unknown, difficulty: .referent),
        TestCase("Show me that again", .unknown, difficulty: .referent)
    ]

    /// LEGITIMATELY EMPTY OBJECT. All must be ACCEPTED.
    /// These are complete requests that simply have no object to name,
    /// and they are the reason the exemption exists in the first place.
    /// If the new rule rejects any of these, it is too aggressive.
    static let shouldAccept: [TestCase] = [
        // [C]
        TestCase("Play something relaxing", .playMusic, difficulty: .medium),
        TestCase("Wake me up at seven", .setReminder, difficulty: .medium),
        TestCase("Make it a little dimmer", .adjustSetting,
                 object: "brightness", difficulty: .hard),
        TestCase("Put on a podcast", .playMusic, difficulty: .easy),

        // [A]
        TestCase("Play my yoasobi music", .playMusic,
                 object: "yoasobi", difficulty: .medium),
        TestCase("Remind me to do my taxes", .setReminder,
                 object: "taxes", difficulty: .medium),
        TestCase("Change master bedroom lights to 100%", .adjustSetting,
                 object: "lights", difficulty: .medium)
    ]
}

//
//  NOTE ON "Make it a little dimmer"
//
//  This one is deliberately uncomfortable. It contains "it", which is
//  exactly the trigger the new rule looks for, but it is a complete
//  and executable request: dimming refers to brightness, and no
//  external referent is needed.
//
//  If the rule rejects it, the rule is matching on surface form rather
//  than on whether the request can actually be carried out. That is a
//  genuine limitation of string matching and it belongs in the writeup
//  rather than being quietly engineered around.
//
//  The same tension already exists in TestSuite with "Make it warmer
//  in here", which currently passes because the model fills the object
//  with "temperature" rather than leaving it empty. That it passes is
//  luck, not design.
//
