# DECISIONS.md

Why ScamCheck is built the way it is. Newest entries at the bottom. Each entry: the decision, the alternatives, and the reason.

---

## Setup

### Project lives in `~/Developer`, not Desktop or Documents
- **Alternatives:** Desktop or Documents (the defaults Xcode offers).
- **Why:** On this Mac both are synced to iCloud. iCloud syncing can corrupt Git repositories and confuse Xcode while it builds. `~/Developer` is local only; GitHub will be the backup.

### Deployment target iOS 27.2
- **Alternatives:** iOS 26, which would reach more phones.
- **Why:** This is a portfolio app tested on one iPhone (iOS 27.2.1). Targeting the latest version keeps the code simpler (no checks for older iOS) and matches the "latest stable iOS" principle. Can be lowered later if needed.

### Free Apple Account, no paid developer program (yet)
- **Why:** Enough to run on my own iPhone. Builds on the device expire after about 7 days, which is fine for development. To revisit in Phase 6 if a Share Extension or App Intent needs a paid account.

---

## Phase 1: Skeleton and UI

### A `MessageAnalyzer` protocol with a fake `MockAnalyzer` first
- **Alternatives:** build the rules straight into the view model.
- **Why:** The UI should not care where an answer comes from. With a protocol, I can swap mock → rules → LLM → combined by changing one line in `ScamCheckApp.swift`, and tests can pass in any analyzer.

### A `Reason` can only be created if its quote is in the message
- **Alternatives:** store whatever quote an analyzer gives and check it later.
- **Why:** Making invalid evidence impossible to represent means no screen can ever show an invented quote, whatever analyzer produced it. Phase 4's "reject quotes not in the message" rule is then enforced everywhere, not just in one place.

### Store where each quote is (a `TextSpan`), counted in Characters
- **Alternatives:** search for the quote again when drawing the highlight; store UTF-16 or byte offsets.
- **Why:** Searching again could highlight a different occurrence of the same words. Character counts are what a person sees (one emoji = 1), so they are easy to test and explain.
- **Known limitation:** only the first occurrence of a phrase is found.

### Highlighting logic is plain Swift (`MessageHighlighter`), not inside the view
- **Why:** Overlapping highlights are easy to get wrong. Plain Swift can be unit tested without the UI.

### Highlights use background colour AND bold; verdicts use icon AND words AND colour
- **Why:** Information shouldn't depend on colour alone (colour blindness, dark mode, VoiceOver).

### `PasteButton` instead of reading the clipboard in code
- **Why:** Reading the clipboard in code makes iOS show an "Allow Paste?" prompt. With `PasteButton`, tapping it is the permission, so no prompt appears.

### The result appears as a sheet (card) over the input screen
- **Alternatives:** show it below the text box; push a new screen.
- **Why:** It reads as one card with a clear Dismiss, and the message stays in the box so the user can edit and check again.

### "Looks fine" says plainly that it is not a guarantee
- **Why:** Honesty. The app can miss scams, and the wording should not suggest otherwise.

### Data types are marked `nonisolated`
- **Why:** This Xcode project runs all app code on the main thread by default (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`). The analysis types are plain data with no UI, so marking them `nonisolated` lets tests and background work use them freely.

### Metrics: `Suspicious` counts as a scam prediction (provisional)
- **Why:** F0.5 needs two classes. Counting Suspicious as "scam" is the stricter choice for precision: if the app wrongly says Suspicious about a real bank alert, that counts against it. **To confirm before Phase 5.**
