//
//  ContentView.swift
//  ScamCheck
//
//  WHAT THIS FILE IS
//  The input screen: a short explanation, a box for the message, a Paste
//  button, a Clear button and the Check button. When a result arrives it
//  slides up as a card (ResultCardView).
//
//  WHY PasteButton
//  SwiftUI's PasteButton lets the user paste without iOS showing the
//  "Allow Paste?" prompt, because tapping it is already clear permission.
//  Reading the clipboard silently in code would trigger that prompt.
//
import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: CheckViewModel

    private var isChecking: Bool { viewModel.state == .checking }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Paste a text, UPI request, delivery notice or job offer. ScamCheck shows what looks risky and why. You decide what to do.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                messageBox

                HStack {
                    PasteButton(payloadType: String.self) { strings in
                        // Hop to the main thread before touching UI state.
                        Task { @MainActor in viewModel.paste(strings) }
                    }
                    .labelStyle(.titleAndIcon)

                    Spacer()

                    if !viewModel.messageText.isEmpty {
                        Button("Clear") { viewModel.clear() }
                            .disabled(isChecking)
                    }
                }

                Button {
                    Task { await viewModel.check() }
                } label: {
                    HStack {
                        if isChecking {
                            ProgressView()
                            Text("Checking…")
                        } else {
                            Text("Check")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!viewModel.canCheck)

                if case .failed(let message) = viewModel.state {
                    Label(message, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red)
                        .font(.callout)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("ScamCheck")
            .sheet(item: $viewModel.result) { result in
                ResultCardView(result: result) {
                    viewModel.dismissResult()
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var messageBox: some View {
        TextEditor(text: $viewModel.messageText)
            .frame(minHeight: 180)
            .padding(8)
            .scrollContentBackground(.hidden)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .topLeading) {
                if viewModel.messageText.isEmpty {
                    Text("Message to check")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityLabel("Message to check")
    }
}

#Preview("Empty") {
    ContentView(viewModel: CheckViewModel(analyzer: MockAnalyzer()))
}

#Preview("With a message") {
    let viewModel = CheckViewModel(analyzer: MockAnalyzer())
    viewModel.messageText = "URGENT: your account will be blocked today. Share the OTP to verify."
    return ContentView(viewModel: viewModel)
}
