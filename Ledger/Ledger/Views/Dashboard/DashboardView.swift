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
    @State private var drilldown: CategoryDrilldown?
    @State private var flowDrilldown: MonthFlow?
    /// Whether the Total Balance card is expanded to reveal the per-account breakdown.
    @State private var isBalanceExpanded = false

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    content(viewModel)
                } else {
                    LoadingView()
                }
            }
            .navigationTitle("Dashboard")
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
                    monthSummaryCard(viewModel)
                    categoryChartCard(viewModel)
                    NavigationLink {
                        SafeToSpendDetailView()
                    } label: {
                        safeToSpendCard(viewModel)
                    }
                    .buttonStyle(.pressable)
                    budgetCard(viewModel)
                    recentTransactionsSection(viewModel)
                }
                .padding()
            }
            .accentWash(.dashboard)
        }
    }

    /// First-run guidance: a blank dashboard should say what to do, not just that it's empty.
    private var onboardingCard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(LinearGradient.brand)
                    Text("Welcome to Ledger")
                        .font(.appTitle2)
                    Text("Three ways to get your money in — pick whichever fits.")
                        .font(.appSubheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 24)

                onboardingStep(
                    number: 1,
                    symbol: "banknote",
                    title: "Add an account",
                    detail: "Accounts tab → +. A chequing account with a starting balance is enough to begin."
                )
                onboardingStep(
                    number: 2,
                    symbol: "link",
                    title: "Or connect Wealthsimple",
                    detail: "More → Connect Wealthsimple signs in with your Wealthsimple login and pulls in your Cash account and transactions automatically."
                )
                onboardingStep(
                    number: 3,
                    symbol: "square.and.arrow.down",
                    title: "Or import a file",
                    detail: "More → Import CSV / OFX brings in a statement export from any bank, with automatic deduplication."
                )

                Text("Once transactions are in, Ledger auto-categorizes them, spots recurring bills, and can suggest a monthly budget from your real spending.")
                    .font(.appFootnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding()
        }
        .background(Color.appBackground)
    }

    private func onboardingStep(number: Int, symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(LinearGradient.brand, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Label(title, systemImage: symbol)
                    .font(.appSubheadline.weight(.semibold))
                Text(detail)
                    .font(.appFootnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .strokeBorder(Color.appHairline, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
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
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Accent.checkIn.base)
            }
            .card()
        }
        .buttonStyle(.pressable)
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
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TOTAL BALANCE")
                            .font(.appCaption.weight(.heavy))
                            .tracking(1.2)
                            .foregroundStyle(.white.opacity(0.85))
                        CountingCurrency(value: viewModel.totalBalance)
                            .font(.appDisplay)
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        Text("Across \(viewModel.accounts.count) account\(viewModel.accounts.count == 1 ? "" : "s")")
                            .font(.appCaption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(9)
                        .background(Color.white.opacity(0.2), in: Circle())
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
        .padding(Theme.cardPadding + 4)
        .background(Accent.dashboard.gradient, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .shadow(color: Palette.emeraldDeep.opacity(0.4), radius: 20, y: 10)
    }

    /// The per-account rows shown when the balance card is expanded: account icon, name (with its
    /// institution when known), and the account's own balance — styled in white to sit on the brand
    /// gradient, separated by hairline dividers.
    private func accountBreakdown(_ accounts: [Account]) -> some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(Color.white.opacity(0.25))
                .padding(.vertical, 12)
            ForEach(Array(accounts.enumerated()), id: \.element.persistentModelID) { index, account in
                if index > 0 {
                    Divider()
                        .overlay(Color.white.opacity(0.15))
                        .padding(.vertical, 10)
                }
                HStack(spacing: 12) {
                    Image(systemName: account.type.sfSymbolName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.18), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(account.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                        if let institution = account.institutionName, !institution.isEmpty {
                            Text(institution)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    Spacer(minLength: 8)
                    Text(CurrencyFormatter.string(from: account.currentBalance, currencyCode: account.currencyCode))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
            }
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
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(color.opacity(0.26), in: Circle())
            Text(CurrencyFormatter.string(from: value))
                .font(.appNumber)
                .foregroundStyle(color)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
            HStack(spacing: 3) {
                Text(label).font(.appCaption.weight(.semibold)).foregroundStyle(.secondary)
                if tappable {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
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
                Text("Tap a slice to see its transactions.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
                if viewModel.reservedForBills > 0 {
                    Text("After reserving \(CurrencyFormatter.string(from: viewModel.reservedForBills)) for upcoming bills")
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
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
                Text("of \(CurrencyFormatter.string(from: viewModel.monthBudgetTotal))")
                    .font(.appFootnote)
                    .foregroundStyle(.secondary)
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
                DonutSegment(id: "spent", label: "Spent", value: spentPortion, color: isOver ? .red : .accentColor, isSelectable: false),
                DonutSegment(id: "remaining", label: "Remaining", value: remaining, color: Color(.systemGray4), isSelectable: false)
            ],
            centerCaption: isOver ? "over budget" : "of budget spent",
            centerValueText: "\(percent)%",
            showLegend: false,
            isInteractive: false
        )
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

    private var accentColor: Color { flow == .income ? .green : .red }

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
            }
        }
        .navigationTitle(flow.title)
        .navigationBarTitleDisplayMode(.inline)
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(CurrencyFormatter.string(from: total))
                    .font(.title2.bold())
                    .foregroundStyle(flow == .income ? Color.green : Color.primary)
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
