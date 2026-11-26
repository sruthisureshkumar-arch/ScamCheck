//
//  ContentView.swift
//  ScamCheck
//
//  WHAT THIS FILE IS
//  The input screen: a short explanation, a box for the message, a Paste
//  button, a Clear button and the Check button. When a result arrives it
//  slides up as a card (ResultCardView).
//
//  PHASE 6 POLISH
//  - Scrolls, so very large text sizes (Dynamic Type) never cut anything off.
//  - Empty state: "Try an example" fills in a synthetic message, so a first-
//    time user (or an interviewer) can see the app work in one tap.
//  - A short privacy note: checks run on this iPhone.
//  - VoiceOver hints on the controls.
//
//  WHY PasteButton
//  SwiftUI's PasteButton lets the user paste without iOS showing the
//  "Allow Paste?" prompt, because tapping it is already clear permission.
//  Reading the clipboard silently in code would trigger that prompt.
//

import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: CheckViewModel

    #if DEBUG
    @State private var showingDebugLog = false
    #endif

    private var isChecking: Bool { viewModel.state == .checking }

    var body: some View {
        NavigationStack {
            ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Paste a text, UPI request, delivery notice or job offer. ScamCheck shows what looks risky and why. You decide what to do.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if viewModel.options.count > 1 {
                    Picker("Checker", selection: $viewModel.selectedOptionID) {
                        ForEach(viewModel.options) { option in
                            Text(option.title).tag(option.id)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(isChecking)
                    .accessibilityHint("Choose how messages are checked: rules and AI together, rules only, or AI only.")
                }

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
                .accessibilityHint(viewModel.canCheck ? "Checks the message for warning signs." : "Paste or type a message first.")

                if case .failed(let message) = viewModel.state {
                    Label(message, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red)
                        .font(.callout)
                }

                if viewModel.messageText.isEmpty && !isChecking {
                    emptyState
                }

                Label("Checks run on this iPhone. Your message isn't sent to any server.", systemImage: "lock.shield")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("ScamCheck")
            #if DEBUG
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingDebugLog = true
                    } label: {
                        Label("Debug log", systemImage: "ladybug")
                    }
                }
            }
            .sheet(isPresented: $showingDebugLog) {
                DebugLogView(log: .shared)
            }
            #endif
            .sheet(item: $viewModel.result) { result in
                ResultCardView(result: result) {
                    viewModel.dismissResult()
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.background)   // solid, so text behind doesn't show through
            }
        }
    }

    /// Shown when the box is empty: what to do, plus one-tap examples.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Not sure what to paste?")
                .font(.headline)
            Text("Copy a message you're unsure about from Messages, WhatsApp or email, then tap Paste. Or try an example:")
                .font(.callout)
                .foregroundStyle(.secondary)
            Menu {
                ForEach(Self.examples, id: \.title) { example in
                    Button(example.title) { viewModel.paste([example.text]) }
                }
            } label: {
                Label("Try an example", systemImage: "text.bubble")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    /// Invented (synthetic) examples. Not real messages.
    private static let examples: [(title: String, text: String)] = [
        ("Fake bank KYC alert", "URGENT: your SBI account will be blocked today. Share the OTP to verify at sbi-kyc-update.com"),
        ("Genuine OTP message", "482913 is your OTP for login to XYZ Bank. Do not share it with anyone."),
        ("Job offer asking for a fee", "Congratulations! You are selected for a work from home job. Pay a registration fee of Rs 499 to get your offer letter."),
        ("Real delivery update", "Your Amazon order has shipped and will arrive tomorrow. Track it at https://www.amazon.in/progress-tracker"),
    ]

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
