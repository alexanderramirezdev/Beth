# B.E.T.H.

**Basic Everyday Task Helper**

A voice assistant that runs entirely on your Mac, and a research harness that measures how well it actually works.

Built on Apple's on-device foundation model (AFM 3 Core, roughly 3 billion parameters). No API key, no account, no network required for inference. Free, private, offline.

---

## The two halves

**Chat.** You talk or type, Beth answers, and she reads the reply back. The model itself has no clock, no network, and little world knowledge, so she calls tools written in ordinary Swift when she needs something she does not carry: current date and time, live weather, optionally location. The model decides *what* is needed. Your code goes and gets it.

**Action Lab.** A benchmark. It runs 32 test sentences through the model, three trials each, and measures how reliably natural language converts into structured app actions. Reports intent accuracy, object extraction, stability across trials, latency, and the performance of a deterministic validator that catches the model's main failure mode.

The Chat tab is the product. The Action Lab is the reason any of the numbers in FINDINGS.md exist.

---

## Why the name undersells

Because the thing undersells. This model cannot tell you the capital of France. It maps "throw some coffee on the list too" to `addItem / coffee / list` at 92% accuracy in about a second, offline, on a laptop.

That is not a small thing. It is just a *specific* thing, and the name says so. A parser, not an oracle.

---

## The files

| File | Job |
|---|---|
| `BethApp.swift` | Entry point |
| `RootView.swift` | Two-tab shell |
| `ContentView.swift` | The chat interface |
| `BethViewModel.swift` | Coordinator between UI and services |
| `BethBrain.swift` | The model session, personality, and tool registry |
| `SpeechRecognizer.swift` | Microphone to text |
| `SpeechSynthesizer.swift` | Text to speech |
| `AskBethIntent.swift` | Siri and Shortcuts entry point |
| `WeatherTool.swift` | Weather and date/time tools |
| `LocationTool.swift` | CoreLocation tool (optional) |
| `AppAction.swift` | The `@Generable` action schema |
| `ActionMapper.swift` | Runs one sentence to one action, timed |
| `ActionValidator.swift` | Deterministic post-hoc check |
| `TestSuite.swift` | 32 benchmark cases in four tiers |
| `ActionLabViewModel.swift` | Experiment runner and scoring |
| `ActionLabView.swift` | Lab interface |
| `Secrets.swift` | Unused placeholder; kept for the cloud path |

---

## Setup

**1. New project.** Xcode, File, New, Project, **macOS** tab, **App**. Name it `Beth`. SwiftUI interface.

**2. Add all the Swift files.** Replace the generated `BethApp.swift` and `ContentView.swift`, add the rest.

**3. Permission strings.** Project icon, Beth target, **Info** tab:
- `Privacy - Microphone Usage Description` → `Beth listens so you can ask questions by voice.`
- `Privacy - Speech Recognition Usage Description` → `Beth converts your speech to text on this Mac.`
- Only if using `LocationTool`: `Privacy - Location When In Use Usage Description`

**4. Sandbox capabilities.** Same target, **Signing and Capabilities**, under App Sandbox:
- **Audio Input** — required, or the mic fails silently
- **Outgoing Connections (Client)** — required, or every tool call fails with a DNS-looking error
- **Location** — only if using `LocationTool`

**5. Apple Intelligence on.** System Settings, Apple Intelligence and Siri. On, and finished downloading.

**6. Run.** Cmd R.

---

## Known behavior worth expecting

She will not know the date unless the date tool fires. She will not know where you are unless you tell her. She will refuse questions outside her knowledge rather than guess, which is deliberate — see FINDINGS.md section 3 for what happens when you leave a small model room to guess.

Chained tool use ("do I need a jacket") requires two dependent calls and is meaningfully harder than a single call. Expect occasional failures there.

---

## Related documents

- `FINDINGS.md` — the pilot study: results, mechanism, three interventions, limitations
- `PHASE-2.md` — what turns the pilot into a contribution, including the deferred spatial HUD
