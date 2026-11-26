//
//  DebugLog.swift
//  ScamCheck
//
//  WHAT THIS FILE IS
//  A small local log of everything that went wrong (or nearly wrong) while
//  analysing messages: AI unavailable, unusable answers, retries, dropped
//  reasons, fallbacks to the rules, and rules/AI disagreements.
//
//  WHERE IT LIVES
//  A file on the phone, in the app's private Application Support folder
//  (debug-log.jsonl, one JSON entry per line). Nothing is sent anywhere.
//  The last 500 entries are kept.
//
//  PRIVACY
//  In Debug builds (what Xcode runs) each entry includes the first 80
//  characters of the message, so failures can be copied into
//  WRONG_ANSWERS.md. In Release builds the message text is NOT stored.
//
//  WHY AN `actor`
//  Several checks could write at the same time. An actor makes Swift run
//  its methods one at a time, so the file can't be corrupted.
//

import Foundation
import os

nonisolated enum DebugEvent: String, Codable, Sendable, CaseIterable {
    case aiUnavailable
    case aiFailed
    case guidedBlockedUsedJSON
    case invalidAnswer
    case retrySucceeded
    case reasonRejected
    case fellBackToRules
    case rulesAndAIDisagreed
}

nonisolated struct DebugLogEntry: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let event: DebugEvent
    let detail: String
    let messagePreview: String?
}

actor DebugLog {

    nonisolated static let shared = DebugLog(fileURL: DebugLog.defaultFileURL)

    nonisolated static var defaultFileURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("debug-log.jsonl")
    }

    nonisolated static let maxEntries = 500
    nonisolated static let previewLength = 80

    /// nil = keep in memory only (used by tests).
    private let fileURL: URL?
    private var loaded: [DebugLogEntry]?
    private let logger = Logger(subsystem: "ScamCheck", category: "analysis")

    init(fileURL: URL?) {
        self.fileURL = fileURL
    }

    func record(_ event: DebugEvent, detail: String, message: String?) {
        var entries = allEntries()
        entries.append(DebugLogEntry(
            id: UUID(),
            date: Date(),
            event: event,
            detail: detail,
            messagePreview: Self.preview(of: message)
        ))
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
        loaded = entries
        save(entries)
        logger.notice("\(event.rawValue, privacy: .public): \(detail, privacy: .public)")
    }

    /// Oldest first.
    func entries() -> [DebugLogEntry] {
        allEntries()
    }

    func clear() {
        loaded = []
        save([])
    }

    /// Entries formatted ready to paste into WRONG_ANSWERS.md.
    func markdown() -> String {
        let formatter = ISO8601DateFormatter()
        let lines = allEntries().map { entry in
            var line = "- \(formatter.string(from: entry.date)) · **\(entry.event.rawValue)** · \(entry.detail)"
            if let preview = entry.messagePreview {
                line += "\n  - Message: \"\(preview)\""
            }
            return line
        }
        return "### Debug log export\n" + lines.joined(separator: "\n")
    }

    // MARK: - Private

    private nonisolated static func preview(of message: String?) -> String? {
        #if DEBUG
        guard let message else { return nil }
        let oneLine = message.replacingOccurrences(of: "\n", with: " ")
        return oneLine.count > previewLength ? String(oneLine.prefix(previewLength)) + "…" : oneLine
        #else
        return nil
        #endif
    }

    private func allEntries() -> [DebugLogEntry] {
        if let loaded { return loaded }
        var result: [DebugLogEntry] = []
        if let fileURL, let text = try? String(contentsOf: fileURL, encoding: .utf8) {
            let decoder = JSONDecoder()
            for line in text.split(separator: "\n") {
                if let entry = try? decoder.decode(DebugLogEntry.self, from: Data(line.utf8)) {
                    result.append(entry)
                }
            }
        }
        loaded = result
        return result
    }

    private func save(_ entries: [DebugLogEntry]) {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        let lines = entries.compactMap { try? encoder.encode($0) }.map { String(decoding: $0, as: UTF8.self) }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data(lines.joined(separator: "\n").utf8).write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Could not write debug log: \(error.localizedDescription, privacy: .public)")
        }
    }
}
