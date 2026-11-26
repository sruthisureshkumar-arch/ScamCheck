//
//  EvaluationHarness.swift
//  ScamCheckTests
//
//  WHAT THIS FILE IS
//  The tools for measuring how well an analyzer does on the labelled
//  dataset in eval_messages.json:
//  - EvalItem: one labelled message (id, message, label, category)
//  - ConfusionMatrix: counts of right/wrong answers + precision, recall, F0.5
//  - EvalReport: everything from one run, printable as Markdown
//
//  DEFINITIONS (positive class = scam)
//  - "Flagged" = the analyzer said Suspicious OR Likely scam.
//    (Suspicious counts as flagged: if the app says Suspicious about a real
//    bank alert, that's a false alarm the user sees. See DECISIONS.md.)
//  - Precision = of the messages flagged, how many were really scams.
//  - Recall    = of the real scams, how many were flagged.
//  - F0.5      = one score that weights precision TWICE as much as recall,
//                because wrongly flagging a genuine message is the worse error.
//                F0.5 = 1.25 · P · R / (0.25 · P + R)
//  - If an analyzer throws (e.g. the AI is unavailable), that message counts
//    as NOT flagged, and is listed under "Errors".
//

import Foundation
@testable import ScamCheck

struct EvalItem: Codable, Sendable, Equatable {
    let id: String
    let message: String
    /// "scam" or "legit"
    let label: String
    let category: String

    var isScam: Bool { label == "scam" }
}

private final class BundleToken {}

enum EvalDataset {
    enum LoadError: Error { case fileNotFound }

    static func load() throws -> [EvalItem] {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: "eval_messages", withExtension: "json")
            ?? bundle.url(forResource: "eval_messages", withExtension: "json", subdirectory: "Evaluation")
        else { throw LoadError.fileNotFound }
        return try JSONDecoder().decode([EvalItem].self, from: Data(contentsOf: url))
    }
}

struct ConfusionMatrix: Equatable, Sendable {
    var truePositives = 0   // scam, flagged
    var falsePositives = 0  // legit, flagged      ← the error we care most about
    var trueNegatives = 0   // legit, not flagged
    var falseNegatives = 0  // scam, not flagged

    var total: Int { truePositives + falsePositives + trueNegatives + falseNegatives }

    var precision: Double {
        let flagged = truePositives + falsePositives
        return flagged == 0 ? 0 : Double(truePositives) / Double(flagged)
    }

    var recall: Double {
        let scams = truePositives + falseNegatives
        return scams == 0 ? 0 : Double(truePositives) / Double(scams)
    }

    func fScore(beta: Double) -> Double {
        let p = precision, r = recall
        let b2 = beta * beta
        let denominator = b2 * p + r
        return denominator == 0 ? 0 : (1 + b2) * p * r / denominator
    }

    var f05: Double { fScore(beta: 0.5) }

    mutating func add(isScam: Bool, flagged: Bool) {
        switch (isScam, flagged) {
        case (true, true): truePositives += 1
        case (false, true): falsePositives += 1
        case (false, false): trueNegatives += 1
        case (true, false): falseNegatives += 1
        }
    }
}

struct EvalReport: Sendable {
    struct Miss: Sendable {
        let item: EvalItem
        let verdict: Verdict?
        let evidence: [String]
        let error: String?
    }

    let analyzerName: String
    var matrix = ConfusionMatrix()
    var misses: [Miss] = []
    var errorCount = 0

    static func flagged(_ verdict: Verdict) -> Bool { verdict != .looksFine }

    /// Runs `analyzer` over every item, one at a time.
    static func run(_ analyzerName: String, analyzer: any MessageAnalyzer, on items: [EvalItem]) async -> EvalReport {
        var report = EvalReport(analyzerName: analyzerName)
        for item in items {
            do {
                let result = try await analyzer.analyze(item.message)
                let isFlagged = flagged(result.verdict)
                report.matrix.add(isScam: item.isScam, flagged: isFlagged)
                if isFlagged != item.isScam {
                    report.misses.append(Miss(
                        item: item,
                        verdict: result.verdict,
                        evidence: result.reasons.map { "\($0.category.rawValue): \"\($0.quote)\"" },
                        error: nil
                    ))
                }
            } catch {
                report.errorCount += 1
                report.matrix.add(isScam: item.isScam, flagged: false)
                if item.isScam {
                    report.misses.append(Miss(item: item, verdict: nil, evidence: [], error: String(describing: error)))
                }
            }
        }
        return report
    }

    /// One line for the history table in EVALUATION.md / README.md.
    var summaryRow: String {
        String(format: "| %@ | %.2f | %.2f | **%.2f** | %d | %d | %d | %d | %d |",
               analyzerName, matrix.precision, matrix.recall, matrix.f05,
               matrix.truePositives, matrix.falsePositives, matrix.trueNegatives, matrix.falseNegatives, errorCount)
    }

    var markdown: String {
        var lines: [String] = []
        lines.append("")
        lines.append("===== ScamCheck evaluation: \(analyzerName) (\(matrix.total) messages) =====")
        lines.append("")
        lines.append("| Analyzer | Precision | Recall | F0.5 | TP | FP | TN | FN | Errors |")
        lines.append("|---|---|---|---|---|---|---|---|---|")
        lines.append(summaryRow)
        lines.append("")
        lines.append("Confusion matrix (rows = truth, columns = app):")
        lines.append("")
        lines.append("|            | Flagged | Not flagged |")
        lines.append("|------------|---------|-------------|")
        lines.append("| **Scam**   | \(matrix.truePositives) | \(matrix.falseNegatives) |")
        lines.append("| **Legit**  | \(matrix.falsePositives) | \(matrix.trueNegatives) |")
        lines.append("")
        lines.append("Misclassified (\(misses.count)):")
        if misses.isEmpty { lines.append("- none") }
        for miss in misses {
            let kind = miss.item.isScam ? "MISSED SCAM" : "FALSE ALARM"
            let verdict = miss.verdict.map(\.title) ?? "error"
            lines.append("- \(miss.item.id) [\(miss.item.category)] \(kind) → \(verdict): \"\(miss.item.message)\"")
            if !miss.evidence.isEmpty { lines.append("  - evidence: \(miss.evidence.joined(separator: "; "))") }
            if let error = miss.error { lines.append("  - error: \(error)") }
        }
        lines.append("===== end =====")
        return lines.joined(separator: "\n")
    }
}
