//
//  ResultCardView.swift
//  ScamCheck
//
//  WHAT THIS FILE IS
//  The card that shows an answer:
//    1. the verdict (icon + words + colour, so it never relies on colour alone)
//    2. what that verdict means for the user
//    3. each reason, with the exact words that triggered it
//    4. the full message with those words highlighted
//    5. a reminder that the app never acts on its own, and a Dismiss button
//
//  It only displays an AnalysisResult; it makes no decisions itself.
//

import SwiftUI

struct ResultCardView: View {
    let result: AnalysisResult
    let onDismiss: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VerdictHeader(verdict: result.verdict)

                Text(guidance)
                    .font(.body)

                if !result.reasons.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(result.verdict == .looksFine ? "Worth noticing" : "Why")
                            .font(.headline)
                        ForEach(result.reasons) { reason in
                            ReasonRow(reason: reason)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Your message")
                        .font(.headline)
                    Text(highlightedMessage)
                        .accessibilityLabel("Your message")
                        .accessibilityValue(result.message)
                        .accessibilityHint(result.reasons.isEmpty
                            ? "Nothing highlighted."
                            : "Highlighted words: " + result.reasons.map(\.quote).joined(separator: ", "))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        .textSelection(.enabled)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("ScamCheck never blocks or deletes messages. You decide what to do.")
                    switch result.source {
                    case .mock:
                        Text("Checked by the demo analyzer. This is not real scam detection yet.")
                    case .rules:
                        Text("Checked with built-in rules on your phone. Rules can miss new tricks.")
                    case .llm:
                        Text("Checked by Apple's on-device AI. Your message didn't leave your phone. AI can be wrong, so look at the highlighted words yourself.")
                    case .combined:
                        Text("Checked with built-in rules and Apple's on-device AI. Your message didn't leave your phone. Each reason says which one found it.")
                    }
                    if let confidence = result.confidence {
                        Text("AI confidence: \(Int((confidence * 100).rounded()))%")
                    }
                    ForEach(result.notes, id: \.self) { note in
                        Text(note)
                    }
                    if result.hiddenReasonCount > 0 {
                        Text(result.hiddenReasonCount == 1
                             ? "1 AI reason was hidden because its quote wasn't in your message."
                             : "\(result.hiddenReasonCount) AI reasons were hidden because their quotes weren't in your message.")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
            }
            .padding()
        }
    }

    /// What the verdict means in practice. Honest about uncertainty.
    private var guidance: String {
        switch result.verdict {
        case .likelyScam:
            "Several warning signs. Don't reply, pay, or share any code. If it claims to be your bank, contact them using the number on your card or their official app."
        case .suspicious:
            "Some warning signs. Before acting, check with the sender through a channel you already trust."
        case .looksFine where result.reasons.isEmpty:
            "No warning signs found. That isn't a guarantee, so stay careful with links and payment requests."
        case .looksFine:
            "No strong warning signs, but there's one thing worth noticing below. Stay careful with links and payment requests."
        }
    }

    /// The message with every quoted phrase highlighted.
    private var highlightedMessage: AttributedString {
        let segments = MessageHighlighter.segments(
            for: result.message,
            highlighting: result.reasons.map(\.span)
        )
        var output = AttributedString()
        for segment in segments {
            var piece = AttributedString(segment.text)
            if segment.isHighlighted {
                // Background colour + bold, so the highlight isn't colour-only.
                piece.backgroundColor = .yellow.opacity(0.35)
                piece.font = .body.bold()
                piece.underlineStyle = .single   // still visible in dark mode / high contrast
            }
            output += piece
        }
        return output
    }
}

// MARK: - Pieces of the card

private struct VerdictHeader: View {
    let verdict: Verdict

    var body: some View {
        Label {
            Text(verdict.title)
                .font(.title2.bold())
        } icon: {
            Image(systemName: symbolName)
                .font(.title2)
        }
        .foregroundStyle(color)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Verdict: \(verdict.title)")
    }

    private var symbolName: String {
        switch verdict {
        case .likelyScam: "exclamationmark.octagon.fill"
        case .suspicious: "exclamationmark.triangle.fill"
        case .looksFine: "checkmark.shield.fill"
        }
    }

    private var color: Color {
        switch verdict {
        case .likelyScam: .red
        case .suspicious: .orange
        case .looksFine: .green
        }
    }
}

private struct ReasonRow: View {
    let reason: Reason

    /// Where this reason came from, and how much it counts.
    private var label: String {
        switch reason.origin {
        case .ai: "AI finding"
        case .rules: reason.strength == .strong ? "Rules · strong sign" : "Rules · weak sign"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label(reason.category.title, systemImage: reason.category.symbolName)
                    .font(.subheadline.bold())
                Spacer()
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("“\(reason.quote)”")
                .font(.callout.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.yellow.opacity(0.35), in: RoundedRectangle(cornerRadius: 4))

            Text(reason.explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

#Preview("Likely scam") {
    let message = "URGENT: your account will be blocked today. Share the OTP to verify."
    let reasons = [
        Reason(category: .urgencyOrThreat, quote: "URGENT", explanation: "Scammers rush you so you act before thinking.", in: message),
        Reason(category: .credentialRequest, quote: "OTP", explanation: "Banks never ask you to share an OTP.", in: message),
    ].compactMap { $0 }
    return ResultCardView(
        result: AnalysisResult(message: message, verdict: .likelyScam, reasons: reasons, source: .mock),
        onDismiss: {}
    )
}

#Preview("Looks fine") {
    ResultCardView(
        result: AnalysisResult(message: "See you at 6 near the station.", verdict: .looksFine, reasons: [], source: .mock),
        onDismiss: {}
    )
}
