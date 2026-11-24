# CLAUDE.md — ScamCheck

Instructions for any AI assistant working on this repo. Read this file fully before writing or changing code.

## What this app is

ScamCheck is an iOS app. A person pastes or shares a message (SMS, UPI request, delivery notice, job offer, payment link) and gets:

1. a **verdict**: `Likely scam`, `Suspicious`, or `Looks fine`
2. the **reasons** behind it
3. the **exact phrases** in the message that triggered each reason, highlighted

The answer must be clear enough that a non-technical person can decide what to do. Start from the person's problem. Keep the design simple and honest.

This is a portfolio project. The owner must be able to explain every line in an interview, so clarity beats cleverness.

## Non-negotiable principles

1. **Stack:** SwiftUI, latest stable iOS (confirm the exact version with the owner; do not assume), MVVM, Swift only. **No third-party dependencies** (no SPM packages, no CocoaPods).
2. **The user decides.** The app never blocks, deletes, reports, or acts on a message by itself. It shows a verdict and evidence, and the user chooses what to do.
3. **Validate every LLM answer before showing it.** Treat model output as untrusted input. Decode strictly, check every field, and verify every quote exists in the original message.
4. **Precision over recall.** Calling a genuine bank alert a scam is worse than missing one scam. The headline metric is **F0.5** (positive class = scam). When unsure, prefer `Suspicious` over `Likely scam`.
5. **Do not invent APIs.** If you are not certain an Apple API exists, or how it behaves on the target iOS version, say so plainly and tell the owner to check the current Apple documentation. Do not write code against a guessed signature without flagging it.
6. **No secrets in the repo.** API keys live only in a local, gitignored config file (e.g. `Config/Secrets.xcconfig`). Commit a `Secrets.example.xcconfig` with placeholder values instead. Before any commit, check that no key is staged.
7. **Synthetic data only.** Every test and evaluation message is invented. Never use real people's messages, phone numbers, UPI IDs, account numbers, or names. Use obviously fake values (e.g. `example-bank.test`, `user@okfake`).
8. **Keep the two logs up to date:**
   - `DECISIONS.md` — each significant choice, the alternatives, and why.
   - `WRONG_ANSWERS.md` — every time the model *or the assistant* got something wrong: what happened, how it was caught, what changed.
9. **Explain every file in plain language.** Each new file gets a short header comment saying what it does and why it exists. After each phase, give a plain-language walkthrough of the files that changed.

## Architecture

MVVM with a swappable analyzer.

```
View (SwiftUI)  →  ViewModel (@MainActor, observable)  →  MessageAnalyzer (protocol)
                                                            ├─ MockAnalyzer        (Phase 1)
                                                            ├─ RuleBasedAnalyzer   (Phase 2)
                                                            ├─ LLMAnalyzer         (Phase 3)
                                                            └─ CombinedAnalyzer    (Phase 4)
```

Core types (shape may be refined, but keep the idea):

- `Verdict`: `.likelyScam`, `.suspicious`, `.looksFine`
- `ReasonCategory`: urgency/threat, credential request (OTP/PIN/password), payment/UPI collect request, suspicious link, sender–link mismatch, fee for prize/job, other
- `Reason`: category, matched quote (exact substring of the message), plain-language explanation, and the quote's range in the message for highlighting
- `AnalysisResult`: verdict, reasons, source (rules / LLM / combined), optional confidence
- `protocol MessageAnalyzer { func analyze(_ message: String) async throws -> AnalysisResult }`

Rules:
- Views contain no analysis logic. ViewModels contain no networking or parsing details.
- Analysis code (rules, validation, combining) is pure Swift with no UI imports, so it can be unit tested.
- A quote is only valid if it is an exact substring of the original message. Highlighting uses the stored range, never a re-search that could match a different spot.

## Combining rules and LLM (Phase 4 policy)

- `Likely scam` only when rules and LLM agree, or when the evidence is strong (define "strong" explicitly in code and in DECISIONS.md).
- Disagreement or weak evidence → `Suspicious`.
- Invalid JSON or missing fields → retry once with the error message → if still invalid, fall back to the rule-based result.
- Any LLM reason whose quote is not in the message is dropped.
- Every failure is written to a local debug log and summarised in WRONG_ANSWERS.md.

## Testing and evaluation

- Every rule has unit tests for cases that **should** trigger and cases that **must not** (e.g. a genuine OTP delivery message, a real-looking bank balance alert).
- The evaluation dataset is JSON: `id`, `message`, `label` (`scam` | `legit`), `category`. The owner reviews and edits it.
- The eval target prints precision, recall, F0.5, a confusion matrix, and every misclassified message. It must be easy to run before and after a change.
- `Suspicious` counts as a scam prediction for metrics unless DECISIONS.md says otherwise. Record the choice there.

## How to work in this repo

- **Build in phases.** Do only the current phase. Do not start the next one without the owner's go-ahead.
- **At the end of each phase, stop and report:**
  1. exactly what to run (Xcode scheme, simulator/device, test command)
  2. what to test by hand, step by step
  3. what is most likely to break, and why
  4. a plain-language explanation of each file added or changed
  5. any API you were unsure about, with a note to check the docs
- Prefer small, readable code over abstractions the project does not need yet.
- If a request conflicts with these principles, point out the conflict before doing anything.
- For risky features (Share Extension, App Intents, on-device model availability), explain the risks and limits **before** building.

## Project facts (checked against the actual project, not assumed)

- Xcode 27 stores the project as `ScamCheck.xcodeproj/project.xcproj`, a JSON-style file (not the older `project.pbxproj`). Do not hand-edit it unless there is no other way; change settings in Xcode.
- The `ScamCheck`, `ScamCheckTests` and `ScamCheckUITests` folders are synchronized folders: any `.swift` file placed inside one is automatically part of that target. No project-file edits are needed to add files. If files are added from outside Xcode while it is open, quit and reopen Xcode (then Clean Build Folder) before building, or Xcode may not compile them.
- Build settings worth knowing: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (app target code is main-actor by default; mark pure analysis types `nonisolated` or keep them free of actor state where that matters), `SWIFT_APPROACHABLE_CONCURRENCY = YES`, `SWIFT_VERSION = 5.0` language mode.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`).

## Phases

1. Skeleton and UI — input screen, result card, `MockAnalyzer` behind `MessageAnalyzer`.
2. Rule-based checks — pure Swift, structured reasons with quotes, full unit tests.
3. LLM analyzer — strict JSON (verdict, confidence 0–1, reasons), Codable decoding. Prefer Apple's on-device Foundation Models framework if the owner's Xcode and device support it; otherwise a swappable remote LLM with the key in local config. Check current docs and record the choice in DECISIONS.md.
4. Handling wrong answers — retry, fallback, quote check, conservative combining, failure logging.
5. Evaluation harness — dataset format, 40 synthetic messages (20 scam, 20 legit, including tricky legit ones), metrics test target.
6. Polish — VoiceOver labels, Dynamic Type, dark mode, empty state, privacy note; Share Extension or App Intent only if realistic, risks stated first.
7. README — problem, how it works, architecture diagram, eval results before/after, what the model got wrong, limitations, next steps.

## Owner's environment

- Mac: Apple silicon M4, macOS Tahoe 26.6.2
- Xcode: 27.2
- Deployment target: iOS 27.2 (set by the Xcode template; matches the test device)
- Project location: `~/Developer/ScamCheck` (kept out of iCloud-synced Desktop/Documents on purpose)
- Test device: iPhone 17 Pro, iOS 27.2.1 (Apple Intelligence capable; confirm it is turned on before Phase 3)
- Apple Developer account: free Apple Account only (no paid program). On-device builds expire after about 7 days; check any Phase 6 capability against free-account limits before building it.
- Phase 3 plan: on-device Foundation Models is the first choice. Verify the current API and availability checks in Apple's docs before writing code. The app must still work through the rule-based analyzer when the model is unavailable (e.g. Apple Intelligence off, model still downloading, or running in a Simulator without support).
