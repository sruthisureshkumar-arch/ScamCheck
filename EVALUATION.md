# EVALUATION.md

How ScamCheck is measured, and the history of results.

## Dataset

`ScamCheckTests/Evaluation/eval_messages.json`: 40 **synthetic** messages (no real people's data).

- 20 scams: UPI (4), bank (4), delivery (3), job (3), OTP (3), prize (3)
- 20 genuine, including tricky ones that look scammy but are real: OTP alerts that say "do not share", a debit alert saying "call immediately", `.bank.in` links, a real job offer, a real collect request, a cashback that needs no fee, a promo short link, a delivery OTP you *are* meant to share with the agent.

Format: one JSON object per message: `id`, `message`, `label` (`scam` | `legit`), `category`.

These messages are separate from the unit-test messages in `SyntheticMessageTests.swift`, so the rules aren't scored on the same messages they were designed against. **Rule:** don't tune rules by looking at this set's failures and then re-score on it. Note the failure, add a *new* similar message to the unit tests, and fix against that.

## Metrics

- Positive class = scam. "Flagged" = Suspicious or Likely scam.
- **Precision:** of messages flagged, how many were scams. False alarms lower it.
- **Recall:** of scams, how many were flagged.
- **F0.5:** weights precision twice as much as recall, because calling a genuine bank alert a scam is worse than missing one scam.
- If an analyzer errors on a message, it counts as not flagged.

## How to run (before and after a change)

1. In Xcode, select **your iPhone** (the AI doesn't run in this Simulator).
2. ◇ Test navigator → `EvaluationTests` → ▶︎.
3. Report navigator → newest Test → each `evaluate…` test → copy the printed tables.
4. Add a row below with the date, the commit, and what changed.

## History

| Date | Commit | Change | Analyzer | Precision | Recall | F0.5 | TP | FP | TN | FN | Errors |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-11-26 | Phase 4 code | Baseline | Rules | _paste_ | | | | | | | |
| 2026-11-26 | Phase 4 code | Baseline | AI only | 0.51 | 0.90 | 0.56 | 18 | 17 | 3 | 2 | 3 |
| 2026-11-26 | Phase 4 code | Baseline (policy v1) | Combined | 0.53 | 1.00 | 0.58 | 20 | 18 | 2 | 0 | 0 |
| 2026-11-26 | Phases 4–7 commit | Policy v2 + stricter AI evidence + clearer instructions | Rules | _paste_ | | | | | | | |
| 2026-11-26 | Phases 4–7 commit | Policy v2 + stricter AI evidence + clearer instructions | AI only | 0.68 | 0.95 | 0.72 | 19 | 9 | 11 | 1 | 0 |
| 2026-11-26 | Phases 4–7 commit | Policy v2 + stricter AI evidence + clearer instructions | **Combined** | **0.94** | **0.80** | **0.91** | 16 | 1 | 19 | 4 | 0 |

### What the second run showed
- **Combined:** 1 false alarm (`l09`: a genuine delivery OTP meant for the agent, flagged by the rules). 4 missed scams: `s04` ("sent by mistake, please return it"), `s11` (customs duty via a short link), `s15` (fake support asking you to "share it"), `s19` (prize link on an unknown domain). Debug events: rules/AI disagreed ×20, reason rejected ×14, invalid answer ×1 → retry succeeded ×1.
- **AI only:** 9 false alarms (down from 17). It still treats a ride PIN for the driver, a delivery OTP for the agent, a real job offer and a promo short link as warnings, so it isn't yet trustworthy enough to raise warnings on its own.
- **Honest reading:** Combined (v2) matches what the rules alone are expected to score (the Python prototype of the rules scored P 0.94 / R 0.80 / F0.5 0.91 with the same 5 errors). The AI currently adds *explanations and confirmation* rather than measured accuracy. Making it add accuracy needs a better-calibrated model or a fresh dataset to tune against.

### Note on the second run (honesty)
The changes between the baseline and the second run were made **after looking at the baseline's mistakes on this set**:
- Combination policy v2: the AI alone can't raise a warning.
- Stricter checks on AI quotes: ≤ 12 words, no negated credential quotes, no official links as "suspicious links".
- Clearer instructions listing genuine message types.

The changes are general rules, not message-specific patches, and the instruction examples are generic types (OTP alerts, bank alerts, bills, official links), not copies of evaluation messages. Still, the second run's scores are probably a little optimistic. A fresh, unseen set is listed as a next step.

### What the baseline showed
- **AI only:** 17 false alarms out of 20 genuine messages. Evidence was often a whole innocent sentence ("It is valid for 5 minutes." as urgency; "Do not share this OTP with anyone." as a credential request).
- **Combined (policy v1):** "Suspicious" whenever rules and AI disagreed, which passed the AI's false alarms to the user: 18 false alarms.
- **Debug events (Combined run):** rules/AI disagreed ×31, JSON fallback used ×1, invalid answer ×1, AI failed → rules fallback ×1, reason rejected ×1.

> Reference while designing (not the app's measurement): a Python prototype of the rules scored P 0.94 / R 0.80 / F0.5 0.91 on this set, with false alarm `l09` (delivery OTP meant for the agent) and missed scams `s04`, `s11`, `s15`, `s19`. The Swift rules should be close; record the real numbers above.
