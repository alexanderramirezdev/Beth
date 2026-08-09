# Phase 2: Turning a Pilot Into a Contribution

The pilot answered "does this work on one model." A dissertation needs "what is true across models, and what should a designer do about it." This document is the plan for getting there.

Ordered by leverage per hour of work.

---

## Step 0: Close out the pilot (this weekend, ~1 hour)

Do not start Phase 2 with loose ends behind you.

- [ ] Rerun the validator at 3 trials. The 94% is currently a single draw.
- [ ] Add the narrow rule for "Play it again": for object-exempt intents, reject when `object` is empty **and** the sentence contains a referring expression. "Put on something upbeat" must stay accepted.
- [ ] Relabel "Tell her I said sorry" to `unknown` and record the reason and date in FINDINGS.md.
- [ ] Extend stability to cover object extraction, not just intent (see finding 5d).
- [ ] Clamp confidence to 0.0 to 1.0 on read and count violations (finding 5c).
- [ ] Commit the whole thing to git with the CSVs. Tag it `pilot-v1`.

That last one is not bookkeeping. Every number in FINDINGS.md should be traceable to a raw CSV. When someone asks in 2028 where 92% came from, you want a file, not a memory.

---

## Step 1: Multi-model comparison (the core contribution)

**The question:** is the referent failure a property of small models in general, or of Apple's model specifically? And does external validation help all of them equally?

`MLXLanguageModel` runs open-source models from Hugging Face on Apple silicon through the **same** `LanguageModelSession` interface. Your harness already works with it. It is macOS-only in the current beta, which is the platform you are on.

```swift
import MLXFoundationModels
let model = MLXLanguageModel(modelID: "mlx-community/Qwen3-4B-4bit")
let session = LanguageModelSession(model: model, instructions: instructions)
```

**Model ladder to test** (verify current availability on the MLX community Hugging Face org before committing):

| Class | Purpose |
|---|---|
| ~1B, 4-bit | Lower bound. Does it collapse entirely? |
| ~3B, 4-bit | Peer to Apple's model, different training |
| ~4B, 4-bit | Same family, one size up |
| ~7-8B, 4-bit | Where does the referent problem disappear? |
| Apple `SystemLanguageModel` | Your existing baseline |
| Same 7B at 8-bit | Isolates quantization from parameter count |

**What to hold constant:** test suite, instructions, schema, trial count, scoring code, validator. Only the model changes.

**What to report per model:** intent accuracy, per-tier accuracy, object extraction, stability, median and p95 latency, memory footprint, and validator delta.

**The interesting shape of the result** is not a ranking. It is where the curves cross. If Referent accuracy is flat at ~12% from 1B to 4B and then jumps at 7B, you have located a capability threshold. If external validation closes the gap for every model, you have a design rule that does not depend on model choice. Either is a real finding.

**Practical note:** this is the experiment your Mac Mini M4 with 24GB was bought for. A 7B at 4-bit is roughly 4GB of weights; 8-bit roughly 8GB. Budget disk for the larger ones and expect the first download of each to be slow.

---

## Step 2: A defensible test set

32 hand-written cases is the weakest part of the pilot. Fix it before scaling models, or you will run a great experiment on a bad benchmark.

**Target: 150 to 200 cases.**

- **Do not write them all yourself.** You wrote the sentences, the labels, and the system under test. That is three roles that should not be one person.
- **Get a second labeler.** Have someone independently label a subset (40 to 50 cases) without seeing your labels. Report inter-annotator agreement (Cohen's kappa). If agreement is poor, your categories are ambiguous and that is worth knowing before you build on them.
- **Sample real phrasing where possible.** Public voice-assistant command corpora, Shortcuts community examples, or a small elicitation exercise ("say how you would ask a phone to do X") beat sentences invented to probe a hypothesis.
- **Keep the probe tiers.** Referent-style adversarial cases stay, clearly labeled as adversarial, reported separately from the naturalistic set. Do not blend them into a single headline number.
- **Expand the action space.** Seven intents is small enough that the task may be artificially easy. Twenty-plus intents is closer to a real app surface and will likely surface confusion patterns that seven cannot.

---

## Step 3: Statistics that survive scrutiny

- **n=5 trials minimum**, ideally 10 for headline comparisons.
- **Report confidence intervals**, not point estimates. Wilson intervals for proportions.
- **Use a paired test for model comparisons.** McNemar's test is the right tool when the same cases are run through two systems. "Model A got 84% and model B got 79%" means nothing without it.
- **Pre-register your hypotheses.** Write down what you expect before each run. This project already produced one instance of a noise artifact being read as a real 12-point effect. Pre-registration is the cheapest available protection against that, and it costs one paragraph.
- **Report the negative results.** The failed interventions in section 4 of FINDINGS.md are as valuable as the successful one, and more credible.

---

## Step 4: Speech in the loop

Everything so far assumes perfect text input. Real voice assistants do not have that.

Feed the test sentences through `SFSpeechRecognizer` (synthesized TTS input, or record yourself reading them) and rerun. Two questions:

1. How much accuracy is lost to transcription error before the model ever sees the text?
2. Do ASR errors interact with the referent problem, or are they independent?

This is a smaller experiment than Step 1 and makes the whole thing substantially more credible, because it measures the actual pipeline rather than one component of it.

---

## Step 5: The routing question, answered with data

The pilot killed the obvious design: confidence thresholds do not work (finding 5b). That leaves the question open, which is better than leaving it assumed.

Once Step 1 gives per-case accuracy for several models, you can ask empirically:

- Which cases does the small model get wrong that a larger one gets right? Is that set predictable from surface features (sentence length, presence of a referring expression, number of clauses)?
- Can a cheap classifier, or the validator itself, decide when to escalate? **The validator is already a routing signal**: a rejection is a request the local model could not handle. Measuring escalation precision using rejections instead of confidence is a direct next experiment and costs almost nothing to run.
- What is the actual cost curve? Escalating 20% of traffic to a cloud model has a measurable latency and dollar cost. Plot accuracy against that cost.

That last question is the one with a genuine contribution in it, and it is reachable from where you are standing.

---

## Step 5.5: The spatial HUD (deferred until hardware)

Captured now because the idea is fresh, not because it is next.

### The blocker is hardware, not skill

The visionOS simulator ships no Foundation Models weights, so nothing in the Chat tab can run there. This needs a Vision Pro, and therefore a paid developer account. Until then the aesthetic work is worth prototyping on macOS, where everything runs.

### What ports for free

SwiftUI is shared. Moving the macOS build back to visionOS cost two lines in each direction: `glassBackgroundEffect()` and the `windowStyle:` argument on `#Preview`. The audio layer is the real work (`AVAudioSession` exists on visionOS and not on macOS), and that file is already written.

### Design direction

The reference is the Spider-Man PS5 HUD: information that appears when relevant and dissolves when it is not. The discipline is subtraction. A HUD that is always fully visible is not a HUD, it is a window with the frame removed.

**Palette.** Near-black translucent ground (`#0B0F14` at low opacity), a single cool accent for active states (`#4DD4E8`), a warm signal color reserved exclusively for errors and refusals (`#E8A33D`), and text in two weights of off-white (`#E8EDF2`, `#8FA0AD`). Two accent colors total. On passthrough, saturation reads much hotter than it does on a monitor, so pick values that look slightly underpowered in the simulator.

**Type.** One face, three sizes, heavy tracking on the small utility text. Spatial UI at arm's length punishes tight letterspacing far more than a desktop display does. Avoid a second typeface; on a translucent ground, contrast between weights carries hierarchy better than contrast between families.

**The signature element.** A live waveform that is the microphone state rather than an indicator next to it. Not a pulsing circle with a mic glyph. The visible amplitude ring *is* the listening affordance, it grows from the point of gaze, and it collapses into the answer text when speech ends. One idea, executed precisely, and everything else in the interface stays quiet.

**Motion.** Two transitions only: a fade-and-scale on appearance, and the waveform collapse. Resist ambient animation. On a headset, anything that moves without reason competes with the room behind it and reads as noise within about ninety seconds.

**Layout.** Corner-anchored, not centered. Center-anchored panels sit exactly where a person wants to look at the world.

### Technical notes for when you get there

- `glassBackgroundEffect()` is the native version of this material. Do not rebuild it with custom blurs.
- Ornaments attach controls to the edge of a window without spending space inside it. Right primitive for a mute toggle or a clear button.
- Decide early between a plain window, a volume, and an immersive space. A HUD in the Spider-Man sense wants an immersive space or a window with a very small footprint; a volume is for objects with depth, which this is not.
- Gaze position is not readable by apps for privacy reasons. Anything that should follow the user's attention has to be driven by head pose or explicit interaction instead. Design around that constraint rather than discovering it late.
- Hand tracking and eye tracking do not work in the simulator. Interaction design cannot be validated without the device.

### The honest risk

A HUD is the most fun part of this project and the least load-bearing. It does not improve accuracy, latency, or any measurement in FINDINGS.md. Build it because it is the thing you actually wanted, but do not let it consume time budgeted for Steps 1 through 4. Ship the research first.

---

## Step 6: Grounding (the other half of the topic)

Everything so far maps language to a *structured action*. Your dissertation topic also covers mapping that action to an *actual UI element*. Different problem, harder, and correctly deferred until the mapping half has numbers.

When you get there, the surface is App Intents and the accessibility tree. The specific research question: when the resolved action does not correspond to any exposed intent, what should the system do? That is the "action space mismatch" problem you identified before writing a line of code, and it is where the spatial/visionOS angle becomes genuinely interesting rather than decorative.

---

## Suggested sequencing

| When | What |
|---|---|
| This weekend | Step 0 |
| Next 2 weeks | Step 2 (test set) in parallel with SwiftUI study |
| Weeks 3 to 6 | Step 1 (multi-model), with Step 3 statistics from the start |
| Weeks 7 to 8 | Step 4 (ASR), write up Steps 1 to 4 |
| Later | Steps 5 and 6 |

Step 2 before Step 1 is deliberate. Running six models against a weak benchmark produces six weak results.

---

## One caution

The pilot took a single day and produced findings that felt significant in the moment. Several of them were, and one of them was noise that looked exactly the same from the inside.

The discipline that caught it (repeated trials, holding variables fixed, writing predictions down first) is the actual transferable skill here, more than any individual result. Keep doing that as this scales and the work will hold up. Stop doing it and the scale will just produce more confident errors.
