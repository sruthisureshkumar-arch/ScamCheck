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

---

## Phase 2: Rule-based checks

### Each warning sign is "strong" or "weak"
- **Strong** (rare in genuine messages): asking you to share an OTP/PIN/password/CVV; "enter PIN / scan QR to receive money"; a fee to get a prize or job; a lookalike link; a link to a raw IP address; a message naming a brand but linking elsewhere.
- **Weak** (common in scams, but also in real messages): urgency/threat words; link shorteners; a plain UPI collect request.
- **Why:** Treating every sign the same would call real messages Suspicious too often. Precision matters more than recall here.

### The verdict policy (VerdictPolicy.swift)
- Count *different kinds* of sign. Two strong kinds, or one strong + one weak → **Likely scam**. One strong kind alone, or two weak kinds → **Suspicious**. Nothing, or one weak kind → **Looks fine** (the weak sign is still shown as "worth noticing").
- **Alternatives:** any sign → Suspicious (simpler, but a real shop's collect request would be flagged); a numeric score (harder to explain in one sentence).
- **Why:** Easy to explain, easy to test, and conservative. Phase 4 can reuse it.

### Rules avoid known false alarms on purpose
- OTP rule needs a request verb (share/send/tell/...) and ignores it when "do not / never / don't" is nearby, including the curly apostrophe iPhones type (don’t).
- Plain "PIN"/"password" only count as "your PIN/password", so "send me the wifi password" from a friend isn't flagged.
- Urgency ignores "immediately" (real debit alerts say "Not you? Call immediately") and past tense "has been blocked" (real confirmations).
- Fee rule needs BOTH a prize/job word and a fee, so a normal bill isn't flagged.

### Links: `.bank.in` is trusted
- Since 31 Oct 2025, RBI requires Indian banks to use `.bank.in` addresses, and only RBI-regulated banks can register them (sources: RBI circular of 21 Apr 2025, as reported by Business Today and others). So any `.bank.in` link is never called a lookalike.
- Known brands and their real domains are in `KnownBrands.swift`. **That list must be reviewed by hand.** A missing real domain causes a false alarm.

### Regular expressions via NSRegularExpression, prototyped in Python first
- **Alternatives:** Swift's newer `Regex` type.
- **Why:** No Swift compiler was available while designing the rules, so the patterns were checked in a Python prototype against 38 messages first. NSRegularExpression uses the same well-known (ICU) pattern syntax, so the Swift version matches the prototype. The test list in `SyntheticMessageTests.swift` was generated from the prototype's list, so they can't drift apart.

### "Unknown sender" can't be checked
- A pasted message doesn't say who sent it or whether they're in your contacts. So a UPI collect request is only a weak sign. Checking the sender would need the Share Extension (Phase 6), and even then iOS may not provide it.

### Known limitations (accepted for precision)
- Delivery-fee scams ("parcel held, pay Rs 25 redelivery: bit.ly/...") only get a weak "short link" note, because genuine couriers also say "pay Rs 450 on delivery".
- A request phrased with "it" ("please share it with him") after a genuine-looking OTP line isn't caught.
- Brand-name matching inside links can misfire on unrelated words that happen to contain a short brand name (e.g. "job**sbi**n.com" contains "sbi").
- Only English messages are handled.
