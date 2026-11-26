//
//  EvaluationTests.swift
//  ScamCheckTests
//
//  HOW TO RUN (before and after any change)
//  1. Select your iPhone at the top of Xcode (the AI only runs on a device).
//  2. Open the ◇ Test navigator, find "EvaluationTests", click its ▶︎ button.
//  3. Open the Report navigator (last icon on the left) → the newest Test →
//     click the test → read the printed report (or press ⇧⌘C for the console).
//  4. Copy the summary rows into EVALUATION.md with today's date and what changed.
//
//  In the Simulator only the Rules evaluation runs; the AI and Combined ones
//  skip themselves.
//
//  These tests PRINT scores; they don't fail on a low score. A score is a
//  measurement to record, not a pass/fail gate. They DO fail if the dataset
//  is malformed.
//

import Foundation
import Testing
@testable import ScamCheck

struct EvaluationDatasetTests {

    @Test func datasetIsWellFormed() throws {
        let items = try EvalDataset.load()
        #expect(items.count == 40)
        #expect(items.filter(\.isScam).count == 20)
        #expect(Set(items.map(\.id)).count == items.count, "ids must be unique")
        #expect(items.allSatisfy { $0.label == "scam" || $0.label == "legit" })
        #expect(items.allSatisfy { !$0.message.trimmingCharacters(in: .whitespaces).isEmpty })
    }
}

struct ConfusionMatrixTests {

    @Test func metricsMatchHandCalculation() {
        // 16 scams caught, 4 missed, 1 false alarm, 19 genuine left alone.
        let matrix = ConfusionMatrix(truePositives: 16, falsePositives: 1, trueNegatives: 19, falseNegatives: 4)
        #expect(abs(matrix.precision - 16.0 / 17.0) < 1e-9)
        #expect(abs(matrix.recall - 0.8) < 1e-9)
        // F0.5 = 1.25·P·R / (0.25·P + R)
        let p = 16.0 / 17.0, r = 0.8
        #expect(abs(matrix.f05 - 1.25 * p * r / (0.25 * p + r)) < 1e-9)
    }

    @Test func noFlagsMeansZeroNotACrash() {
        let matrix = ConfusionMatrix(truePositives: 0, falsePositives: 0, trueNegatives: 20, falseNegatives: 20)
        #expect(matrix.precision == 0)
        #expect(matrix.f05 == 0)
    }

    @Test func f05WeightsPrecisionMoreThanRecall() {
        let precise = ConfusionMatrix(truePositives: 10, falsePositives: 0, trueNegatives: 20, falseNegatives: 10)
        let eager = ConfusionMatrix(truePositives: 20, falsePositives: 10, trueNegatives: 10, falseNegatives: 0)
        #expect(precise.f05 > eager.f05)
    }
}

struct EvaluationRunTests {

    @Test func evaluateRules() async throws {
        let items = try EvalDataset.load()
        let report = await EvalReport.run("Rules", analyzer: RuleBasedAnalyzer(), on: items)
        print(report.markdown)
        #expect(report.matrix.total == items.count)
        #expect(report.errorCount == 0)
    }

    @Test(
        .enabled(if: OnDeviceModelSmokeTests.canRunRealModel, "Needs a real device with the on-device model"),
        .timeLimit(.minutes(15))
    )
    func evaluateAIOnly() async throws {
        let items = try EvalDataset.load()
        let ai = OnDeviceLLMAnalyzer(log: DebugLog(fileURL: nil))
        let report = await EvalReport.run("AI only", analyzer: ai, on: items)
        print(report.markdown)
        #expect(report.matrix.total == items.count)
    }

    @Test(
        .enabled(if: OnDeviceModelSmokeTests.canRunRealModel, "Needs a real device with the on-device model"),
        .timeLimit(.minutes(15))
    )
    func evaluateCombined() async throws {
        let items = try EvalDataset.load()
        let log = DebugLog(fileURL: nil)
        let combined = CombinedAnalyzer(ai: OnDeviceLLMAnalyzer(log: log), log: log)
        let report = await EvalReport.run("Combined", analyzer: combined, on: items)
        print(report.markdown)
        let events = await log.entries()
        print("Debug events during Combined run: \(events.count) — " +
              Dictionary(grouping: events, by: \.event).map { "\($0.key.rawValue)×\($0.value.count)" }.sorted().joined(separator: ", "))
        #expect(report.matrix.total == items.count)
    }
}
