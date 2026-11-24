# WRONG_ANSWERS.md

Every time the model (or the AI assistant helping build this) got something wrong: what happened, how it was caught, and what changed. Newest at the bottom.

Format:
- **Date / phase**
- **Who was wrong:** app's model / rules / AI assistant
- **What happened**
- **How it was caught**
- **What changed**

---

### 2026-11-24 · Setup
- **Who was wrong:** AI assistant (Claude)
- **What happened:** Said that in Xcode's New Project window, the iOS tab would be along the top of the first window. Xcode 27 has a new welcome screen where New Project is a dropdown; the iOS templates are under **Choose Template…**.
- **How it was caught:** My screenshot showed the dropdown with no iOS option.
- **What changed:** Used Choose Template… → iOS → App. Lesson: instructions about Xcode's UI can be out of date; check against the screen.

### 2026-11-24 · Setup
- **Who was wrong:** nobody, but nearly
- **What happened:** Xcode 27 stores the project as `project.xcproj` (a JSON-style file), not the older `project.pbxproj`. An assistant assuming the old format could have "fixed" a healthy project.
- **How it was caught:** The assistant read the actual project files before writing any code.
- **What changed:** Recorded in CLAUDE.md under "Project facts" so it isn't assumed again.

### Known wrong behaviour to fix in Phase 2 (from the mock)
- **Who is wrong:** `MockAnalyzer` (on purpose; it is a fake)
- **What happens:** A genuine "Your OTP is 482913. Do not share it with anyone." is marked **Suspicious**, because "OTP" is a demo phrase.
- **What must change:** Phase 2 rules must only flag requests to *share* a code, with a must-NOT-trigger unit test for a genuine OTP message.

### 2026-11-25 · Phase 1
- **Who was wrong:** AI assistant (Claude)
- **What happened:** Wrote the new Swift files into the project folder while Xcode was open and said they would "appear on their own". Xcode didn't notice them, so the first build failed with 8 "Cannot find … in scope" errors (only the two original files were being compiled).
- **How it was caught:** The first ⌘B failed; the errors all pointed at types defined in the new files.
- **What changed:** Quit and reopened Xcode, then Clean Build Folder. Build succeeded. Added to CLAUDE.md: after files are added from outside Xcode, reopen the project before building.

### 2026-11-25 · Phase 2 — FIXED: mock flagged a genuine OTP
- **Who was wrong:** `MockAnalyzer` (Phase 1, on purpose)
- **What happened:** "Your OTP is 482913. Do not share it with anyone." was marked Suspicious.
- **How it was caught:** Predicted in Phase 1 and logged above.
- **What changed:** The app now uses `RuleBasedAnalyzer`. `CredentialRequestRule` needs a request verb and skips negated requests. Must-not-trigger tests cover genuine OTP messages, including the curly apostrophe in "don’t".

### 2026-11-25 · Phase 2 — design: curly apostrophes
- **Who was wrong:** AI assistant (first draft of the rules)
- **What happened:** The first negation pattern only knew "don't" with a straight apostrophe. iPhones type "don’t" (curly) by default, so a genuine "Please don’t share it" OTP would have been flagged.
- **How it was caught:** Reviewing the prototype before writing Swift.
- **What changed:** The pattern accepts both apostrophes; a test covers each.

### 2026-11-25 · Phase 2 — design: "send me the wifi password"
- **Who was wrong:** AI assistant (first draft of the rules)
- **What happened:** The first credential rule flagged any "send ... password", so a friend asking for the wifi password would have been called Suspicious.
- **How it was caught:** Adding more must-not-trigger messages to the prototype.
- **What changed:** Plain "PIN"/"password" now only count as "your PIN/password". OTP, CVV, UPI PIN still count on their own.

### Known misses (accepted, to revisit with the language model)
- "OTP 4412 do not share. Our agent will call, please share it with him." → Looks fine (should be Suspicious).
- "Your parcel is held at our warehouse. Pay Rs 25 redelivery: bit.ly/3xYz9" → Looks fine with a short-link note (should be at least Suspicious).
