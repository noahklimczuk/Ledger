import SwiftUI
import SwiftData

/// Ask Ledger: a floating, always-available AI chat. It talks to Gemini (the same free key used
/// for budget suggestions) grounded in the current month's plan, recent transactions, and account
/// data, and can take action — building budgets, creating transactions, adding bills and goals,
/// and more — from natural language. See `AskLedgerViewModel`.
struct AskLedgerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let month: Date
    @State private var viewModel: AskLedgerViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    if viewModel.hasAPIKey {
                        chat(viewModel)
                    } else {
                        keyEntry(viewModel)
                    }
                } else {
                    LoadingView()
                }
            }
            .navigationTitle("Ask Ledger")
            .accent(.insights)
            .accentWash(.insights)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    // Only meaningful once the key is set and the chat UI is showing.
                    if let viewModel, viewModel.hasAPIKey {
                        HStack(spacing: 16) {
                            historyMenu(viewModel)
                            Button {
                                viewModel.newChat()
                            } label: {
                                Image(systemName: "square.and.pencil")
                            }
                            .accessibilityLabel("New Chat")
                        }
                    }
                }
            }
            .task {
                if viewModel == nil {
                    viewModel = AskLedgerViewModel(modelContext: modelContext, month: month)
                }
            }
        }
    }

    // MARK: - History

    /// Lists saved conversations, most recent first; tapping one reopens it.
    private func historyMenu(_ viewModel: AskLedgerViewModel) -> some View {
        Menu {
            if viewModel.recentChats.isEmpty {
                Text("No saved chats yet")
            } else {
                Section("Recent Chats") {
                    ForEach(viewModel.recentChats) { chat in
                        Button {
                            viewModel.openChat(chat)
                        } label: {
                            Text(chat.title)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "clock.arrow.circlepath")
        }
        .accessibilityLabel("Chat history")
    }

    // MARK: - Chat

    private func chat(_ viewModel: AskLedgerViewModel) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        intro
                        if !viewModel.hasStarted {
                            starterPrompts(viewModel)
                        }
                        ForEach(viewModel.messages) { message in
                            if message.kind == .actionNote {
                                ActionNote(text: message.text)
                                    .id(message.id)
                            } else {
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                        }
                        if viewModel.isSending {
                            typingIndicator.id(Self.typingID)
                        }
                        if let errorText = viewModel.errorText {
                            Label(errorText, systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(Palette.amber)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: viewModel.messages.count) { _, _ in scrollToEnd(viewModel, proxy) }
                .onChange(of: viewModel.isSending) { _, _ in scrollToEnd(viewModel, proxy) }
                // Jump to the newest message when a saved chat is opened/restored.
                .onAppear {
                    if let last = viewModel.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }

            // The input bar owns its own text as local @State, so typing re-renders only the bar —
            // not this whole view (which would otherwise re-parse every message's Markdown on each
            // keystroke and make input crawl).
            AdvisorInputBar(isSending: viewModel.isSending) { text in
                Task { await viewModel.send(text) }
            }
        }
    }

    private var intro: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(LinearGradient.brand, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text("Ask Ledger")
                    .font(.subheadline.weight(.semibold))
                Text("Ask about this month's plan, where to cut back, or have me build your budget from your transactions — with savings sized to what's left of your income.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func starterPrompts(_ viewModel: AskLedgerViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(viewModel.suggestedPrompts, id: \.self) { prompt in
                Button {
                    Task { await viewModel.send(prompt) }
                } label: {
                    HStack {
                        Text(prompt)
                            .font(.subheadline)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "arrow.up.circle")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSending)
            }
        }
    }

    private var typingIndicator: some View {
        HStack(spacing: 6) {
            ProgressView()
            Text("Thinking…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let typingID = "advisor.typing"

    private func scrollToEnd(_ viewModel: AskLedgerViewModel, _ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if viewModel.isSending {
                proxy.scrollTo(Self.typingID, anchor: .bottom)
            } else if let last = viewModel.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    // MARK: - API key entry

    private func keyEntry(_ viewModel: AskLedgerViewModel) -> some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(LinearGradient.brand)
                    Text("Meet Ask Ledger")
                        .font(.headline)
                    Text("Chat about your budget and spending, grounded in your real numbers, and let it build your monthly budget for you. It runs on Google Gemini's free tier — add a key once to turn it on. Your budget totals and recent transactions (date, amount, category, merchant) are sent — never account names, balances, or notes.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)

            Section {
                SecureField("AIza…", text: Binding(
                    get: { viewModel.apiKeyText },
                    set: { viewModel.apiKeyText = $0 }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                Button("Save Key") { viewModel.saveAPIKey() }
                    .disabled(viewModel.apiKeyText.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: {
                Text("Google Gemini API Key")
            } footer: {
                Text("Free with a Google account — no credit card. Get a key at aistudio.google.com/apikey. Stored in the iOS Keychain only.")
            }
        }
        .scrollContentBackground(.hidden)
    }
}

/// The message composer. Deliberately its own view with a **local** `@State` for the text: keeping
/// the in-progress text out of the observable view model means each keystroke re-renders only this
/// bar, not the whole chat transcript (which was re-parsing every bubble's Markdown per keystroke
/// and making typing lag).
private struct AdvisorInputBar: View {
    let isSending: Bool
    let onSend: (String) -> Void

    @State private var text = ""

    private var canSend: Bool {
        !isSending && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask your advisor…", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .background(.thinMaterial, in: Capsule())

            Button {
                submit()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? AnyShapeStyle(LinearGradient.brand) : AnyShapeStyle(Color.secondary))
            }
            .disabled(!canSend)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isSending, !trimmed.isEmpty else { return }
        onSend(trimmed)
        text = ""
    }
}

/// Centered capsule marking something the advisor *did* (applied a budget), distinct from what it
/// said.
private struct ActionNote: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(.thinMaterial, in: Capsule())
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
    }
}

/// One chat bubble: the user's turns trail right on the accent gradient, the advisor's lead left
/// on a material card. Advisor replies render their (lightweight) Markdown.
private struct MessageBubble: View {
    let message: AskLedgerViewModel.Message

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(rendered)
                .font(.subheadline)
                .foregroundStyle(message.role == .user ? Color.white : Color.primary)
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(bubbleBackground)
            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }

    private var rendered: AttributedString {
        // Advisor replies are Markdown; the user's own text renders literally.
        guard message.role == .assistant else { return AttributedString(message.text) }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: message.text, options: options)) ?? AttributedString(message.text)
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if message.role == .user {
            LinearGradient.brand.clipShape(RoundedRectangle(cornerRadius: 16))
        } else {
            RoundedRectangle(cornerRadius: 16).fill(.thinMaterial)
        }
    }
}

#Preview {
    AskLedgerView(month: .now)
        .modelContainer(for: LedgerSchema.models, inMemory: true)
}
