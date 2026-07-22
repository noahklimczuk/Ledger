import SwiftUI
import SwiftData

/// A tapped spending slice's drill-down target: a real category, or the uncategorized bucket.
private enum CategoryDrilldown: Hashable {
    case category(Category)
    case uncategorized
}

/// A tapped month-summary tile's drill-down target: the month's income or its expenses.
private enum MonthFlow: String, Hashable, Identifiable {
    case income
    case expenses

    var id: String { rawValue }
    var title: String { self == .income ? "Income" : "Expenses" }
}

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRefreshCoordinator.self) private var refresh
    @State private var viewModel: DashboardViewModel?
    @State private var isPresentingCheckIn = false
    @State private var isCheckInDue = false
    @State private var isPresentingNewAccount = false
    @State private var isPresentingNewTransaction = false
    @State private var drilldown: CategoryDrilldown?
    @State private var flowDrilldown: MonthFlow?
    /// Whether the Total Balance card is expanded to reveal the per-account breakdown.
    @State private var isBalanceExpanded = false
    /// Rotates the Ask Ledger briefing card through a few different messages on Home.
    @State private var askLedgerTick = 0

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    content(viewModel)
                } else {
                    LoadingView(message: "Syncing…")
                }
            }
            .navigationTitle("Home")
            .accent(.dashboard)
            .navigationDestination(item: $drilldown) { target in
                switch target {
                case .category(let category):
                    CategoryTransactionsView(category: category, month: .now)
                case .uncategorized:
                    CategoryTransactionsView(uncategorizedForMonth: .now)
                }
            }
            .navigationDestination(item: $flowDrilldown) { flow in
                MonthFlowTransactionsView(flow: flow, month: .now)
            }
            .task {
                if viewModel == nil { viewModel = DashboardViewModel(modelContext: modelContext) }
                viewModel?.load()
                isCheckInDue = DailyCheckInViewModel.isDue()
            }
            .sheet(isPresented: $isPresentingCheckIn, onDismiss: {
                isCheckInDue = DailyCheckInViewModel.isDue()
                viewModel?.load()
            }) {
                DailyCheckInView()
            }
            .sheet(isPresented: $isPresentingNewAccount, onDismiss: { viewModel?.load() }) {
                AccountEditView(account: nil)
            }
            .sheet(isPresented: $isPresentingNewTransaction, onDismiss: { viewModel?.load() }) {
                TransactionEditView(transaction: nil)
            }
            // Reload once a background refresh (sync + categorize) finishes, so balances and
            // recent transactions reflect the latest data without needing to re-open the tab.
            .onChange(of: refresh.refreshCount) { _, _ in viewModel?.load() }
            // Pull-to-refresh runs a real sync; the refreshCount bump above then reloads the VM.
            .refreshable { await refresh.refresh(container: modelContext.container) }
        }
    }

    @ViewBuilder
    private func content(_ viewModel: DashboardViewModel) -> some View {
        if viewModel.accounts.isEmpty {
            onboardingCard
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    if isCheckInDue {
                        checkInCard
                    }
                    balanceCard(viewModel)
                    wellnessCard(viewModel)
                    askLedgerCard(viewModel)
                    monthSummaryCard(viewModel)
                    burnCard(viewModel)
                    NavigationLink {
                        SafeToSpendDetailView()
                    } label: {
                        safeToSpendCard(viewModel)
                    }
                    .buttonStyle(.pressable)
                    if viewModel.budgetRows.isEmpty {
                        budgetCard(viewModel)
                    } else {
                        budgetChannelsCard(viewModel)
                    }
                    categoryChartCard(viewModel)
                    recentTransactionsSection(viewModel)
                }
                .padding()
            }
            .accentWash(.dashboard)
        }
    }

    /// Bloom empty dashboard: warm, minimal, no tutorial copy.
    private var onboardingCard: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 18) {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    gradient: Gradient(colors: [Palette.green.opacity(0.18), Color.clear]),
                                    center: .center,
                                    startRadius: 10,
                                    endRadius: 70
                                )
                            )
                            .frame(width: 130, height: 130)
                        Text("🌱")
                            .font(AppFont.scaled(54, relativeTo: .largeTitle))
                    }
                    .padding(.top, 40)

                    Text("Let's plant your first goal")
                        .font(.appTitle2.weight(.heavy))
                        .multilineTextAlignment(.center)

                    Text("Add an account or a few transactions and your balance, budgets and wellness score will bloom here.")
                        .font(.appSubheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                }

                VStack(spacing: 12) {
                    AccentButton(title: "Add an account", systemName: "banknote", accent: .dashboard) {
                        isPresentingNewAccount = true
                    }

                    Button {
                        isPresentingNewTransaction = true
                    } label: {
                        Text("Add a transaction by hand")
                            .font(.appSubheadline.weight(.heavy))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 10)

                Spacer()
            }
            .padding()
        }
        .accentWash(.dashboard)
    }

    /// Shown on days the check-in hasn't been done yet — the ritual only sticks if the app
    /// does the remembering.
    private var checkInCard: some View {
        Button {
            Haptics.tap()
            isPresentingCheckIn = true
        } label: {
            HStack(spacing: 14) {
                IconBadge(systemName: "checklist", accent: .checkIn, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily Check-In")
                        .font(.appHeadline)
                        .foregroundStyle(Color.primary)
                    Text("2 minutes to review today and keep the plan at zero")
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.appFootnote.weight(.bold))
                    .foregroundStyle(Accent.checkIn.base)
            }
            .card()
        }
        .buttonStyle(.pressable)
    }

    /// Bloom's signature dashboard tile: the Financial Wellness score at a glance, tapping through to
    /// the full breakdown. One number for "how am I doing?".
    private func wellnessCard(_ viewModel: DashboardViewModel) -> some View {
        NavigationLink {
            FinancialWellnessView()
        } label: {
            HStack(spacing: 16) {
                WellnessRing(score: viewModel.wellness.score, size: 76, lineWidth: 9)
                VStack(alignment: .leading, spacing: 4) {
                    Text("FINANCIAL WELLNESS")
                        .font(.appCaption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Text("\(viewModel.wellness.state) \(viewModel.wellness.stateEmoji)")
                        .font(.appTitle3.weight(.heavy))
                        .foregroundStyle(Accent.wellness.deep)
                    Text(viewModel.wellness.summary)
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.appFootnote.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .card()
        }
        .buttonStyle(.pressable)
    }

    /// The "Ask Ledger" briefing — cycles through a handful of insights and prompts so Home never
    /// feels static. Tapping the card opens the full Ask Ledger screen.
    private func askLedgerCard(_ viewModel: DashboardViewModel) -> some View {
        NavigationLink {
            AskLedgerView(month: .now)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    IconBadge(systemName: "sparkles", accent: .insights, size: 30)
                    Text("Ask Ledger")
                        .font(.appHeadline)
                        .foregroundStyle(Color.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.appFootnote.weight(.bold))
                        .foregroundStyle(Accent.insights.base)
                }
                Text(askLedgerMessage(viewModel, tick: askLedgerTick))
                    .font(.appBody)
                    .foregroundStyle(Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.4), value: askLedgerTick)
            }
            .padding(Theme.cardPadding)
            .background(Accent.insights.faintGradient, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Accent.insights.base.opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(.pressable)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4.5))
                guard !Task.isCancelled else { return }
                askLedgerTick += 1
            }
        }
    }

    private func askLedgerMessage(_ viewModel: DashboardViewModel, tick: Int) -> String {
        let messages = askLedgerMessages(viewModel)
        guard !messages.isEmpty else { return "Ask me anything — I'm here to help with your money." }
        return messages[tick % messages.count]
    }

    private func askLedgerMessages(_ viewModel: DashboardViewModel) -> [String] {
        var messages: [String] = []
        if let insight = viewModel.topInsight { messages.append(insight.message) }
        if let tend = viewModel.wellness.toTend.first {
            messages.append("You're doing well. The one thing worth tending this month is \(tend.name.lowercased()).")
        }
        let net = viewModel.monthNet
        messages.append(net >= 0
            ? "You're up \(CurrencyFormatter.string(from: net)) this month."
            : "You're down \(CurrencyFormatter.string(from: abs(net))) this month.")
        messages.append("Safe to spend: \(CurrencyFormatter.string(from: viewModel.safeToSpend)) this month.")
        if viewModel.monthBudgetTotal > 0 {
            let percent = Int((viewModel.monthSpending.doubleValue / viewModel.monthBudgetTotal.doubleValue * 100).rounded())
            messages.append("You've used \(percent)% of your monthly budget.")
        }
        messages.append("Ask me anything — e.g., 'How much did I spend on groceries?'")
        return messages
    }

    /// The Total Balance card. Tapping it expands a clean per-account breakdown in place, so the
    /// single headline number can be unfolded into the accounts that make it up without leaving the
    /// dashboard.
    private func balanceCard(_ viewModel: DashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                Haptics.tap()
                withAnimation(Motion.smooth) { isBalanceExpanded.toggle() }
            } label: {
                HStack(spacing: 18) {
                    BalanceBlob(percent: viewModel.budgetUsedPercent)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TOTAL BALANCE")
                            .font(.appCaption.weight(.heavy))
                            .tracking(1.2)
                            .foregroundStyle(.secondary)
                        CountingCurrency(value: viewModel.totalBalance)
                            .font(.appDisplay)
                            .foregroundStyle(Color.primary)
                            .minimumScaleFactor(0.4)
                            .lineLimit(1)
                        deltaPill(viewModel)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.appSubheadline.weight(.bold))
                        .foregroundStyle(Accent.dashboard.deep)
                        .padding(9)
                        .background(Accent.dashboard.soft, in: Circle())
                        .rotationEffect(.degrees(isBalanceExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Total Balance, \(CurrencyFormatter.string(from: viewModel.totalBalance))")
            .accessibilityHint(isBalanceExpanded ? "Hides accounts" : "Shows all accounts")
            .accessibilityAddTraits(.isButton)

            if isBalanceExpanded {
                accountBreakdown(viewModel.accounts)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    /// The month's net change, as a green/coral pill under the balance figure.
    private func deltaPill(_ viewModel: DashboardViewModel) -> some View {
        let up = viewModel.monthNet >= 0
        let color = up ? Palette.green : Palette.coral
        return Text("\(up ? "▲" : "▼") \(CurrencyFormatter.string(from: abs(viewModel.monthNet))) this month")
            .font(.appCaption.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(color.opacity(0.16), in: Capsule())
    }

    /// The per-account rows shown when the balance card is expanded: account icon, name (with its
    /// institution when known), and the account's own balance — styled in white to sit on the brand
    /// gradient, separated by hairline dividers.
    private func accountBreakdown(_ accounts: [Account]) -> some View {
        VStack(spacing: 0) {
            Divider().padding(.vertical, 12)
            ForEach(Array(accounts.enumerated()), id: \.element.persistentModelID) { index, account in
                if index > 0 {
                    Divider().padding(.vertical, 10)
                }
                HStack(spacing: 12) {
                    IconBadge(systemName: account.type.sfSymbolName, accent: .accounts, size: 30, filled: false)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(account.name)
                            .font(.appSubheadline.weight(.medium))
                        if let institution = account.institutionName, !institution.isEmpty {
                            Text(institution)
                                .font(.appCaption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(CurrencyFormatter.string(from: account.currentBalance, currencyCode: account.currencyCode))
                        .font(.appSubheadline.weight(.semibold))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
            }
            NavigationLink { AccountListView() } label: {
                HStack {
                    Text("All accounts")
                        .font(.appSubheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.appCaption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 14)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - This month: income / expenses / net

    private func monthSummaryCard(_ viewModel: DashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeadline("This Month", subtitle: DateFormatting.monthYear(.now))
            HStack(spacing: 10) {
                // Income and Expenses drill into the month's matching transactions; Net is a
                // derived figure with no single transaction set behind it, so it stays static.
                summaryTile("Income", value: viewModel.monthIncome, color: Palette.income, icon: "arrow.down.right") { flowDrilldown = .income }
                summaryTile("Expenses", value: viewModel.monthSpending, color: Palette.expense, icon: "arrow.up.right") { flowDrilldown = .expenses }
                summaryTile("Net", value: viewModel.monthNet, color: viewModel.monthNet < 0 ? Palette.expense : Palette.indigo, icon: "equal")
            }
        }
    }

    @ViewBuilder
    private func summaryTile(_ label: String, value: Decimal, color: Color, icon: String, action: (() -> Void)? = nil) -> some View {
        if let action {
            Button(action: action) {
                summaryTileBody(label, value: value, color: color, icon: icon, tappable: true)
            }
            .buttonStyle(.pressable)
            .accessibilityHint("Shows this month's \(label.lowercased()) transactions")
        } else {
            summaryTileBody(label, value: value, color: color, icon: icon, tappable: false)
        }
    }

    private func summaryTileBody(_ label: String, value: Decimal, color: Color, icon: String, tappable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(AppFont.scaled(12, relativeTo: .caption, weight: .black))
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(color.opacity(0.26), in: Circle())
            Text(CurrencyFormatter.string(from: value))
                .font(.appNumber)
                .foregroundStyle(color)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .contentTransition(.numericText())
                .animation(.smooth, value: value)
            HStack(spacing: 3) {
                Text(label).font(.appCaption.weight(.semibold)).foregroundStyle(.secondary)
                if tappable {
                    Image(systemName: "chevron.right")
                        .font(AppFont.scaled(9, relativeTo: .caption2, weight: .bold))
                        .foregroundStyle(color.opacity(0.7))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
    }

    @ViewBuilder
    private func categoryChartCard(_ viewModel: DashboardViewModel) -> some View {
        if !viewModel.topCategories.isEmpty {
            card(title: "Top Spending Categories") {
                InteractiveDonutChart(
                    segments: viewModel.topCategories.map { slice in
                        DonutSegment(
                            id: slice.id,
                            label: slice.name,
                            value: slice.amount,
                            color: Color(hex: slice.colorHex)
                        )
                    },
                    centerCaption: "Spent",
                    onSelect: { segment in
                        if let slice = viewModel.topCategories.first(where: { $0.id == segment.id }) {
                            drilldown = slice.category.map(CategoryDrilldown.category) ?? .uncategorized
                        }
                    }
                )
            }
        }
    }

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeadline(title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func safeToSpendCard(_ viewModel: DashboardViewModel) -> some View {
        let ok = viewModel.safeToSpend >= 0
        return HStack(spacing: 14) {
            IconBadge(
                systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                accent: ok ? .goals : .debt,
                size: 44
            )
            VStack(alignment: .leading, spacing: 3) {
                Text("Safe to Spend")
                    .font(.appSubheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(CurrencyFormatter.string(from: viewModel.safeToSpend))
                    .font(.appNumber)
                    .foregroundStyle(ok ? Color.primary : Palette.expense)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .animation(.smooth, value: viewModel.safeToSpend)
                if viewModel.reservedForBills > 0 {
                    Text("After reserving \(CurrencyFormatter.string(from: viewModel.reservedForBills)) for upcoming bills")
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.appFootnote.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .card()
    }

    private func budgetCard(_ viewModel: DashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeadline("Spending vs Budget")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(CurrencyFormatter.string(from: viewModel.monthSpending))
                    .font(.appNumber)
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .animation(.smooth, value: viewModel.monthSpending)
                Text("of \(CurrencyFormatter.string(from: viewModel.monthBudgetTotal))")
                    .font(.appFootnote)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(.smooth, value: viewModel.monthBudgetTotal)
            }
            if viewModel.monthBudgetTotal > 0 {
                budgetGauge(spent: viewModel.monthSpending, budget: viewModel.monthBudgetTotal)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    /// A spent-vs-remaining ring: the spent portion (red once it overruns) against the leftover
    /// budget, with the percentage of the budget used in the centre.
    private func budgetGauge(spent: Decimal, budget: Decimal) -> some View {
        let isOver = spent > budget
        let spentPortion = min(spent, budget)
        let remaining = max(budget - spent, 0)
        let percent = Int((spent.doubleValue / budget.doubleValue * 100).rounded())
        return InteractiveDonutChart(
            segments: [
                DonutSegment(id: "spent", label: "Spent", value: spentPortion, color: isOver ? Palette.expense : .accentColor, isSelectable: false),
                DonutSegment(id: "remaining", label: "Remaining", value: remaining, color: Color(.systemGray4), isSelectable: false)
            ],
            centerCaption: isOver ? "over budget" : "of budget spent",
            centerValueText: "\(percent)%",
            showLegend: false,
            isInteractive: false
        )
    }

    /// Ember's burn-rate idea, in Bloom: a cool→hot meter with the month's average daily spend.
    private func burnCard(_ viewModel: DashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SPENDING BURN RATE")
                    .font(.appCaption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(viewModel.dailyBurnText)
                    .font(.appCaption.weight(.bold))
                    .foregroundStyle(Palette.peachDeep)
                    .contentTransition(.numericText())
                    .animation(.smooth, value: viewModel.dailyBurnText)
            }
            BurnMeter(position: viewModel.burnPosition)
            HStack {
                Text("Cool · saving").font(.appCaption2).foregroundStyle(.secondary)
                Spacer()
                Text("Hot · overspending").font(.appCaption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    /// The month's budgets as Bloom clay channels — the dashboard's headline budget view when
    /// per-category budgets exist.
    private func budgetChannelsCard(_ viewModel: DashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeadline("This Month's Budgets")
            ForEach(Array(viewModel.budgetRows.enumerated()), id: \.element.id) { index, row in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(row.name)
                            .font(.appSubheadline.weight(.semibold))
                        Spacer(minLength: 8)
                        Text("\(CurrencyFormatter.string(from: row.spent)) / \(CurrencyFormatter.string(from: row.allocated))")
                            .font(.appCaption.weight(.semibold))
                            .foregroundStyle(row.isOver ? Palette.coral : .secondary)
                            .monospacedDigit()
                    }
                    ClayChannel(progress: row.progress, isOver: row.isOver, fillAccent: channelAccent(index))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    /// Rotates the clay channels through a few Bloom accents so a list of budgets reads as a set.
    private func channelAccent(_ index: Int) -> Accent {
        let accents: [Accent] = [.dashboard, .budgets, .transactions, .accounts]
        return accents[index % accents.count]
    }

    private func recentTransactionsSection(_ viewModel: DashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeadline("Recent Transactions")
            if viewModel.recentTransactions.isEmpty {
                Text("No transactions yet.")
                    .font(.appFootnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.recentTransactions) { transaction in
                        TransactionRowView(transaction: transaction)
                            .padding(.horizontal)
                        if transaction.persistentModelID != viewModel.recentTransactions.last?.persistentModelID {
                            Divider().padding(.leading)
                        }
                    }
                }
                .padding(.vertical, 8)
                .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .strokeBorder(Color.appHairline, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.05), radius: 14, y: 6)
            }
        }
    }
}

/// The month's income or expense transactions, reached by tapping the dashboard's Income/Expenses
/// tile. The filter mirrors `DashboardViewModel`'s tile math exactly — the calendar month, non-
/// archived accounts, transfers excluded, split by amount sign — so the list totals to the tile.
private struct MonthFlowTransactionsView: View {
    @Environment(\.modelContext) private var modelContext

    let flow: MonthFlow
    let month: Date

    @State private var transactions: [Transaction] = []

    private var total: Decimal {
        transactions.reduce(Decimal(0)) { $0 + abs($1.amount) }
    }

    private var accentColor: Color { flow == .income ? Palette.income : Palette.expense }

    var body: some View {
        Group {
            if transactions.isEmpty {
                EmptyStateView(
                    systemImage: flow == .income ? "arrow.down.circle" : "arrow.up.circle",
                    title: "No Transactions",
                    message: "No \(flow.title.lowercased()) for \(DateFormatting.monthYear(month))."
                )
            } else {
                List {
                    Section { summaryRow }
                    Section("\(transactions.count) transaction\(transactions.count == 1 ? "" : "s")") {
                        ForEach(transactions) { transaction in
                            NavigationLink {
                                TransactionDetailView(transaction: transaction)
                            } label: {
                                TransactionRowView(transaction: transaction)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(flow.title)
        .navigationBarTitleDisplayMode(.inline)
        .accentWash(.dashboard)
        .task(id: flow) { load() }
    }

    private var summaryRow: some View {
        HStack {
            Image(systemName: flow == .income ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(accentColor, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(DateFormatting.monthYear(month))
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
                Text(CurrencyFormatter.string(from: total))
                    .font(.appTitle2.weight(.bold))
                    .foregroundStyle(flow == .income ? Palette.income : Color.primary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func load() {
        let calendar = Calendar.current
        let start = Budget.normalize(month)
        let end = calendar.date(byAdding: DateComponents(month: 1), to: start) ?? start
        let descriptor = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let all = (try? modelContext.fetch(descriptor)) ?? []
        transactions = all.filter { transaction in
            guard transaction.date >= start, transaction.date < end,
                  transaction.countsTowardTotals, !transaction.isTransfer else {
                return false
            }
            switch flow {
            case .income: return transaction.amount > 0
            case .expenses: return transaction.amount < 0
            }
        }
    }
}

private extension Decimal {
    var doubleValue: Double { (self as NSDecimalNumber).doubleValue }
}

#Preview {
    DashboardView()
        .modelContainer(for: LedgerSchema.models, inMemory: true)
        .environment(AppRefreshCoordinator())
}
