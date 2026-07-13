import SwiftUI
import SwiftData

/// The AI financial-advisor chat, opened from the floating bubble on the Budgets screen. It talks
/// to Gemini (the same free key used for budget suggestions) grounded in the current plan and
/// recent transactions, and can build the month's budget on request — including a savings
/// set-aside proportional to income vs. spending. See `AIAdvisorViewModel`.
struct AIAdvisorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let month: Date
    @State private var viewModel: AIAdvisorViewModel?

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
            .navigationTitle("Financial Advisor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if viewModel == nil {
                    viewModel = AIAdvisorViewModel(modelContext: modelContext, month: month)
                }
            }
        }
    }

    // MARK: - Chat

    private func chat(_ viewModel: AIAdvisorViewModel) -> some View {
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
                                .foregroundStyle(.orange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) { _, _ in scrollToEnd(viewModel, proxy) }
                .onChange(of: viewModel.isSending) { _, _ in scrollToEnd(viewModel, proxy) }
            }

            inputBar(viewModel)
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
                Text("Your financial advisor")
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

    private func starterPrompts(_ viewModel: AIAdvisorViewModel) -> some View {
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

    private func inputBar(_ viewModel: AIAdvisorViewModel) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask your advisor…", text: Binding(
                get: { viewModel.input },
                set: { viewModel.input = $0 }
            ), axis: .vertical)
            .lineLimit(1...4)
            .textFieldStyle(.plain)
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .background(.thinMaterial, in: Capsule())
            .onSubmit { send(viewModel) }

            Button {
                send(viewModel)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend(viewModel) ? AnyShapeStyle(LinearGradient.brand) : AnyShapeStyle(Color.secondary))
            }
            .disabled(!canSend(viewModel))
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func canSend(_ viewModel: AIAdvisorViewModel) -> Bool {
        !viewModel.isSending && !viewModel.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send(_ viewModel: AIAdvisorViewModel) {
        guard canSend(viewModel) else { return }
        Task { await viewModel.send(viewModel.input) }
    }

    private static let typingID = "advisor.typing"

    private func scrollToEnd(_ viewModel: AIAdvisorViewModel, _ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if viewModel.isSending {
                proxy.scrollTo(Self.typingID, anchor: .bottom)
            } else if let last = viewModel.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    // MARK: - API key entry

    private func keyEntry(_ viewModel: AIAdvisorViewModel) -> some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(LinearGradient.brand)
                    Text("Meet your financial advisor")
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
    let message: AIAdvisorViewModel.Message

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
    AIAdvisorView(month: .now)
        .modelContainer(for: LedgerSchema.models, inMemory: true)
}
