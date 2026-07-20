import SwiftUI
import SwiftData

/// Ask Ledger — a private, on-device financial advisor. It opens on a warm landing screen with
/// starter prompts, then becomes a conversation of structured, advisor-style answers built from the
/// user's real data. Pushed into an existing navigation stack (from the dashboard card or More), so
/// it registers its own destinations without wrapping another `NavigationStack`.
struct AskLedgerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRefreshCoordinator.self) private var refresh
    @State private var viewModel: AskLedgerViewModel?
    @State private var input = ""

    var body: some View {
        Group {
            if let viewModel {
                VStack(spacing: 0) {
                    if viewModel.hasStarted {
                        conversation(viewModel)
                    } else {
                        landing(viewModel)
                    }
                    AskLedgerInput(text: $input, isDisabled: viewModel.isThinking) {
                        send(viewModel)
                    }
                }
            } else {
                LoadingView()
            }
        }
        .navigationTitle("Ask Ledger")
        .navigationBarTitleDisplayMode(.inline)
        .accent(.insights)
        .background(Color.appBackground.ignoresSafeArea())
        .navigationDestination(for: AskLedgerRoute.self) { route in
            destination(route)
        }
        .toolbar {
            if viewModel?.hasStarted == true {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Haptics.tap()
                        withAnimation(Motion.smooth) { viewModel?.reset() }
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("New conversation")
                }
            }
        }
        .task {
            if viewModel == nil { viewModel = AskLedgerViewModel(modelContext: modelContext) }
            viewModel?.load()
        }
        .onChange(of: refresh.refreshCount) { _, _ in viewModel?.load() }
    }

    // MARK: Landing

    private func landing(_ viewModel: AskLedgerViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(Accent.insights.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: Accent.insights.base.opacity(0.4), radius: 14, y: 8)
                    Text("What would you like\nhelp with today?")
                        .font(.appTitle.weight(.heavy))
                        .foregroundStyle(Color.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("I answer from your real numbers — budgets, savings, subscriptions and what's coming next. Everything stays on your iPhone.")
                        .font(.appSubheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)

                Text("TRY ONE OF THESE")
                    .font(.appCaption2.weight(.bold)).tracking(0.8).foregroundStyle(.secondary)

                VStack(spacing: 10) {
                    ForEach(Array(viewModel.suggestedPrompts.enumerated()), id: \.offset) { _, prompt in
                        PromptSuggestionCard(icon: prompt.icon, text: prompt.text) {
                            input = ""
                            Haptics.tap()
                            viewModel.send(prompt.text)
                        }
                    }
                }
            }
            .padding()
        }
        .accentWash(.insights)
    }

    // MARK: Conversation

    private func conversation(_ viewModel: AskLedgerViewModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(viewModel.turns) { turn in
                        AskLedgerMessageView(turn: turn) { prompt in
                            input = ""
                            viewModel.send(prompt)
                        }
                        .id(turn.id)
                    }
                    Color.clear.frame(height: 1).id(Self.bottomID)
                }
                .padding()
            }
            .accentWash(.insights)
            .onChange(of: viewModel.turns.count) { _, _ in scrollToBottom(proxy) }
            .onChange(of: viewModel.isThinking) { _, _ in scrollToBottom(proxy) }
        }
    }

    private static let bottomID = "ask-ledger-bottom"

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(Motion.smooth) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
    }

    private func send(_ viewModel: AskLedgerViewModel) {
        let text = input
        input = ""
        viewModel.send(text)
    }

    // MARK: Routing

    @ViewBuilder
    private func destination(_ route: AskLedgerRoute) -> some View {
        switch route {
        case .analytics:     ReportsView()
        case .subscriptions: RecurringView()
        case .goals:         SavingsGoalsView()
        case .wellness:      FinancialWellnessView()
        }
    }
}

#Preview {
    NavigationStack {
        AskLedgerView()
    }
    .modelContainer(for: LedgerSchema.models, inMemory: true)
    .environment(AppRefreshCoordinator())
}
