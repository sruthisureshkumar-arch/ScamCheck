//
//  DebugLogView.swift
//  ScamCheck
//
//  WHAT THIS FILE IS
//  A developer-only screen (shown only in Debug builds, via the ladybug
//  button) listing the DebugLog, newest first. "Share" exports the log as
//  Markdown, ready to paste into WRONG_ANSWERS.md.
//

import SwiftUI

struct DebugLogView: View {
    let log: DebugLog

    @Environment(\.dismiss) private var dismiss
    @State private var entries: [DebugLogEntry] = []
    @State private var markdown = ""

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    Text("Nothing logged yet. Failures, retries, fallbacks and disagreements appear here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(entries.reversed()) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.event.rawValue).font(.subheadline.bold())
                            Spacer()
                            Text(entry.date, style: .time).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(entry.detail).font(.callout)
                        if let preview = entry.messagePreview {
                            Text("“\(preview)”").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Debug log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: markdown) {
                        Label("Share as Markdown", systemImage: "square.and.arrow.up")
                    }
                    .disabled(entries.isEmpty)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Clear log", role: .destructive) {
                        Task {
                            await log.clear()
                            await reload()
                        }
                    }
                    .disabled(entries.isEmpty)
                }
            }
            .task { await reload() }
        }
    }

    private func reload() async {
        entries = await log.entries()
        markdown = await log.markdown()
    }
}
