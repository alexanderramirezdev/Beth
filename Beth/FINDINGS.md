# Pilot Study: Natural Language to Structured App Actions on a 3B On-Device Model

**Dates:** August 1 and August 23, 2026
**Platform:** macOS 27 beta, Apple Foundation Models (`SystemLanguageModel`), Swift, `@Generable` constrained decoding
**Status:** Pilot. Not publishable as-is. See Limitations.

> **CRITICAL: two model conditions, not one.**
>
> **Model A** — macOS 27 beta, measured August 1. Build not recorded.
> **Model B** — macOS 26.6.2 release, build 25G83, measured August 23.
>
> The OS was **rolled back** between the two dates (the beta blocked
> App Store Connect submission for an unrelated project). Model B is
> therefore the OLDER, currently-shipping model, not a newer one.
>
> Median latency differs by 40% and the failure signature differs
> completely. The two dates are **not comparable** and are reported
> separately. Model A's build number was never recorded, which is
> itself a finding. See section 5f.

---

## 1. What was tested

Whether a small on-device language model can convert a spoken request into a structured, executable app action: an intent, an object, a container, and a value. This is the mapping half of the natural-language-to-UI-action problem. Grounding (resolving the action against an actual UI element) was not tested.

**Test set:** 32 hand-written sentences across four tiers.

| Tier | n | Character |
|---|---|---|
| Easy | 8 | Explicit verb, plain noun object |
| Medium | 8 | Natural phrasing, implied verb |
| Hard | 8 | Ambiguous or verb-absent, should be refused |
| Referent | 8 | Strong verb, unresolvable referent, should be refused |

**Method:** Fresh `LanguageModelSession` per request (no cross-case contamination). One warmup request discarded before timing. Three trials per case unless noted.

---

## 2. Headline results — Model A (v4 schema, 3 trials, n=96)

| Metric | Value |
|---|---|
| Intent accuracy | 78% |
| Object extraction | 92% |
| Stability (all trials agree) | 100% |
| Per-trial spread | 78 to 78% |
| Median latency | 1.10s |
| Cold start | 2.6 to 2.9s |

Broken out: Easy 100%, Medium 100%, Hard 100%, **Referent 12%**.

Every error in the suite is in one tier.

---

## 3. Principal finding: the model does not distinguish a referring expression from a referent

On the failing cases, the model placed the pronoun itself into the object slot:

| Sentence | Model output |
|---|---|
| "Remove those" | `removeItem`, object: **"those"** |
| "Send it to her" | `sendMessage`, object: **"her"** |
| "Put that on there" | `addItem`, object: **"that"** |
| "Add it" | `addItem`, object: **"it"** |

This is not a failure to notice that the referent is unresolved. From the model's perspective the object field is populated and the request is complete. There is nothing to flag.

**This matters because it predicts why every model-side intervention failed.** Both attempted fixes asked the model to detect a problem it does not represent.

---

## 4. Three interventions, measured — all on Model A

### 4a. Prose instruction (failed)

The system instructions explicitly stated the rule and named the trigger words:

> "If the request refers to something you cannot identify from the sentence alone, such as 'it', 'that', or 'the last one', use the unknown intent..."

Result: Referent 12%. The model violated the stated rule on 7 of 8 cases, at confidences up to 0.80.

**Claim:** stating a rule in the prompt, with examples, did not produce compliance in this model.

### 4b. Structural self-assessment (failed, and harmful)

Added a mandatory boolean field `objectIsIdentifiable`, placed **before** `intent` in declaration order so that autoregressive generation would condition the intent on it. The `@Guide` on `intent` stated it must be `unknown` when the boolean was false.

| Metric | Without field | With field |
|---|---|---|
| Intent | 78% | 74% |
| **Object** | **92%** | **29%** |
| Stability | 100% | 94% |
| Referent | 12% | 12% |

The field did not fix the target problem and cut object extraction by roughly two thirds.

**Mechanism:** across 96 trials the model answered `true` only 11 times, including `false` for plain nouns ("bread", "brightness", "Italian restaurants"). Object extraction tracked that judgment almost perfectly:

- `identifiable: true` → object correct **11 of 11**
- `identifiable: false` → object correct **3 of 37**

The model declared objects unidentifiable, then honored its own declaration by leaving the field empty.

### 4c. External deterministic validation (worked)

A post-hoc code check with two rules:
1. Reject if `object` is a referring expression (closed-class string match).
2. Reject if `intent` requires an object and none was given. `setReminder`, `adjustSetting`, and `playMusic` are exempt, since requests like "Set a reminder for 3pm" are complete without one.

Result (1 trial, n=32, **needs rerun at 3 trials**):

| | Raw | Validated |
|---|---|---|
| Intent accuracy | 78% | **94%** |
| Referent tier | 12% | **88%** |

Validator: 7 rejections, 6 correct, 1 false alarm, precision 86%. Zero added latency, zero inference cost, fully deterministic.

---

## 5. Secondary findings — Model A unless noted

### 5a. Constraint propagation between fields is asymmetric

In experiment 4b, the preceding boolean field measurably suppressed the free-text `object` field but had no detectable effect on the `intent` enum field, in the same struct, in the same generation, despite an explicit `@Guide` instruction linking them.

This is the most novel observation in the study and the least explained. It is directly testable: move the field below `intent`, or change `intent` from an enum to a constrained string, and see whether the asymmetry follows position or type.

### 5b. Self-reported confidence is not usable for routing

Mean confidence when correct: 0.67. When incorrect: 0.63. A separation of 0.04.

Threshold sweep for "escalate to a larger model when confidence < T":

| T | Escalated | Errors caught | Precision | Recall |
|---|---|---|---|---|
| 0.5 | 6 | 1 of 7 | 17% | 14% |
| 0.7 | 13 | 4 of 7 | 31% | 57% |
| 0.8 | 18 | 6 of 7 | 33% | 86% |
| 0.9 | 24 | 7 of 7 | 29% | 100% |

No threshold achieves usable precision and recall together. Reaching full recall requires escalating three quarters of all traffic.

Observed extremes: a correct answer at confidence **0.01**, a wrong answer at **0.80**.

**Implication:** confidence-threshold routing, the obvious design for on-device/cloud hybrid systems, does not work on this model. Routing must be driven by something else.

### 5c. Constrained decoding enforces type, not range

The model emitted `confidence: 100.00` on a field documented as 0.0 to 1.0. `@Generable` guaranteed a `Double`. It did not guarantee a valid `Double`. Any downstream code trusting the documented range would have been silently wrong.

### 5d. Instability is concentrated in extraction, not classification

Across repeated runs, intent classification varied within roughly ±3 points while object extraction varied from 29% to 92% depending on schema. Within a single stable configuration, intent was 100% stable across trials while extraction still flipped on individual cases (e.g. "Remove eggs from the list" produced `eggs`/`list` on trials 1 and 3 and an empty object on trial 2).

Stability as currently measured covers intent only and therefore **overstates** system reliability.

### 5e. Methodological note: single-run evaluation is not measurement

Two consecutive runs of identical code, identical schema, and identical test cases produced object accuracy of **81%** and then **31%**. An earlier apparent 12-point improvement, initially interpreted as a real effect, was sampling noise.

All conclusions in this document rest on 3-trial runs except where explicitly noted.

---

## 5f. The validator was defeated by a model version change

The most important result in this document, and it was found by accident.

The macOS 27 beta was rolled back to the 26.6.2 release between the two measurement dates, for an unrelated reason (the beta blocked App Store Connect submission). This was not an experimental manipulation. It was discovered only because latency dropped 40% and the build stamp, added the same day, disagreed with what was believed to be running.

The validator, which raised intent accuracy from 76% to 92% on Model A, collapsed on Model B.

### Dev set, same 32 cases, same validator code

| | Model A (27 beta, Aug 1) | Model B (26.6.2, Aug 23) |
|---|---|---|
| Raw intent accuracy | 76% | 70% |
| Validated intent accuracy | **92%** | **78%** |
| Validator precision | 86% | 73% |
| Median latency | 1.10s | 0.66s |

Note the direction. **Model B is the older, currently-shipping model.** It is faster and more fluent. It is also the one the validator cannot handle.

### Mechanism: fluency converted a detectable failure into an undetectable one

Model A, when it could not resolve a referent, left evidence. It placed the referring expression itself into the object slot, or left the slot empty. Both are trivially detectable in code, which is precisely why the validator worked.

Model B fills the slot with a plausible invented noun:

| Sentence | Model A | Model B |
|---|---|---|
| "Add it" | object: `it` | object: **`milk`** |
| "Put that on there" | `addItem` | `addItem`, object: **`shopping list`** |
| "The usual" | `unknown` | `addItem`, object: **`milk`** |
| "Remove those" | object: `those` | object: **`eggs`** |
| "Play it again" | object: empty | object: `music` |

`milk`, `eggs`, and `shopping list` appear nowhere in those inputs. They are plausible completions drawn from the surrounding task context, emitted at confidences up to 1.00.

Rule 1 matches referring expressions and cannot match a real noun. Rule 2 requires an empty object and the slot is now full. The validator is not miscalibrated on Model B. It is largely inert.

### Rule 3 fired zero times across 141 trials on Model B

Rule 3 was written to catch object-exempt intents with empty objects. Model B rarely produces empty objects, so the rule never triggered on either suite. It was obsolete before it was first measured.

### A new false alarm appeared

"Remind me when I get there" is correctly `setReminder`. Model B extracts object `there`, Rule 1 rejects it as a referring expression, and a correct answer is destroyed. Three trials, three false alarms. This case was untouched on Model A because Model A extracted a different object.

The validator did not merely stop helping. On this case it started actively hurting.

### One clean regression

"We already got the paper towels" was 3/3 correct on Model A and is 3/3 `addItem` on Model B. The model reads a statement of possession as an instruction to add. Unrelated to the validator; recorded because it is a clear per-case difference between builds.

### Held-out set results (Model B only)

| | Raw | Validated |
|---|---|---|
| Overall | 60% | 62% |
| Should-reject half (24 trials) | 29% | 29% |
| Should-accept half (21 trials) | 100% | **100%** |

Zero false alarms on the accept half. The validator is not too aggressive here; it has nothing to grip.

"Make it a little dimmer", written deliberately to trip Rule 3 on surface form, passed cleanly on all three trials, because Rule 3 never fired.

### The claim

**External validation is coupled to a specific failure signature, and that signature is not stable across model versions.**

The direction of the version change is not the point. Here the model was rolled *back*, and a validator that was correct, tested, honestly measured, and demonstrably effective became inert and in one case harmful. An upgrade would pose the same risk. The fragility is version-coupling itself.

This qualifies the recommendation in section 4c sharply. External validation still outperformed both model-side interventions on Model A. But anyone deploying this pattern against a platform-provided model inherits a silent regression risk on any OS change, with no detection mechanism short of continuously rerunning a benchmark.

### The practical consequence for deployment

Model B is the **shipping** model. Users are on it. The confabulation behavior documented above is production behavior, not beta instability.

Any system that treats an extracted field as trustworthy because it is populated will, on the currently-released Apple on-device model, act on values the user never said.

### What this implies about the next validator

Rules 1 through 3 all encode knowledge of *how* the model fails. That is why they broke.

A **grounding check** does not: it asks whether the extracted value actually appears in the user's input. Confabulation is detectable by definition, because the words are not there. `milk` cannot be grounded in "Add it" under any model. This is the next experiment and the direct prerequisite for any downstream project that trusts extraction output.

---

## 6. Limitations

These are substantial. The study is a pilot.

- **n=32 cases**, hand-written by one person who also wrote the ground truth labels. No external validation of the label set.
- **One model.** Nothing here establishes whether these findings are properties of small models generally or of Apple's model specifically.
- **One prompt family.** Instruction wording was varied informally, not systematically.
- **3 trials.** Enough to detect gross instability, not enough for confidence intervals.
- **Ground truth inconsistency found.** "Send it to her" was labeled `unknown` and "Tell her I said sorry" was labeled `sendMessage`, despite both having an unresolvable recipient. The second label is being revised to `unknown`; this decision was made because the labels contradict each other, not because the validator flagged it. Recording it here because changing ground truth after seeing results requires disclosure.
- **Synthetic input.** Sentences were written to probe categories, not sampled from real user speech.
- **No ASR in the loop.** Real voice input introduces transcription errors upstream that would compound with these results.
- **English only.**
- **Two model conditions, discovered after the fact.** The OS build was not recorded on August 1. Model A and Model B are distinguished by latency and failure signature, not by a logged identifier. Build stamping is now automatic; prior numbers are approximately dated rather than precisely attributed.
- **Both models are betas.** They change without notice and may regress before release. No claim here should be phrased as "Apple's model does X"; it is "this build behaved this way on this date."
- **Held-out authorship was split**: four reject and four accept cases by Claude (which also wrote the validator), four reject and three accept by Alexander. A partial control, not a real one.

---

## 7. Relationship to existing work

The core difficulty here is **anaphora resolution** (also called coreference resolution): determining what a referring expression points to. This is a long-studied problem in computational linguistics, not a new discovery. That small models handle it poorly is unsurprising and should be presented as confirmation, not novelty.

What may be novel, pending a literature check:

1. The specific measurement in an on-device, App-Intents-shaped action space with latency reported alongside accuracy.
2. The finding that a self-assessment field **degraded** extraction accuracy via constraint propagation.
3. The asymmetric propagation between free-text and enum fields under constrained decoding.
4. The negative calibration result for confidence-threshold hybrid routing.

Literature to review before claiming any of these: coreference and anaphora resolution, semantic parsing, slot filling, grammar-constrained decoding, calibration in language models, and hybrid on-device/cloud inference routing.

---

## 8. What this establishes for the dissertation premise

The task does not require world knowledge. On Model A (macOS 27 beta), a small on-device model that cannot answer trivia questions reached 76% intent accuracy raw and 92% with an external validator, at roughly 1.1 seconds on consumer hardware, entirely offline. Model B (macOS 26.6.2, the shipping build) runs the same task at 0.66 seconds and 70% raw.

The premise that lightweight on-device natural language to UI action mapping is viable now has supporting evidence rather than only an argument.

**But section 5f qualifies the deployment story sharply.** Viability of the mapping is established. Viability of *safeguarding* the mapping against a platform-provided model that changes underneath you is not, and that is now the more interesting open question.
