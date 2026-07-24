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
    @State private var isPresentingBudgetList = false
    @State private var isBurnInfoPresented = false
    @State private var editingAccount: Account?
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
            .sheet(isPresented: $isPresentingBudgetList, onDismiss: { viewModel?.load() }) {
                BudgetListView()
            }
            .sheet(item: $editingAccount, onDismiss: { viewModel?.load() }) { account in
                AccountEditView(account: account)
            }
            .sheet(isPresented: $isBurnInfoPresented) {
                if let viewModel {
                    burnInfoSheet(viewModel)
                }
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
                    appHeader
                    statusPills(viewModel)
                    if isCheckInDue {
                        checkInCard
                    }
                    balanceCard(viewModel)
                    if isBalanceExpanded {
                        accountBreakdown(viewModel.accounts)
                            .card()
                    }
                    monthSummaryTiles(viewModel)
                    wellnessStrip(viewModel)
                    burnCard(viewModel)
                    budgetChannelsCard(viewModel)
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
                emptyStateHeader

                VStack(spacing: 18) {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    gradient: Gradient(colors: [Palette.green.opacity(0.20), Color.clear]),
                                    center: .center,
                                    startRadius: 10,
                                    endRadius: 60
                                )
                            )
                            .frame(width: 120, height: 120)
                        Circle()
                            .strokeBorder(Palette.green.opacity(0.40), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                            .frame(width: 120, height: 120)
                        Text("🌱")
                            .font(.system(size: 52))
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
                    AccentButton(title: "Add an account", accent: .dashboard) {
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

    /// The rendering's empty-state header: a welcome line and a small gradient avatar.
    private var emptyStateHeader: some View {
        HStack {
            Text("Welcome 🌿")
                .font(.appHeadline.weight(.heavy))
                .foregroundStyle(Color.primary)
            Spacer()
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Palette.peach, Palette.peri],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 40, height: 40)
                .shadow(color: Color.bloomShadow, radius: 8, x: 3, y: 4)
        }
    }

    // MARK: - Home header + pills

    /// Phone 1 header: "Good morning,\nNoah 🌿 you're blooming" plus a gradient avatar.
    private var appHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Good morning,")
                    .font(.appHeadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Noah 🌿 you're blooming")
                    .font(.appHeadline.weight(.heavy))
                    .foregroundStyle(Color.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Palette.peach, Palette.peri],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 46, height: 46)
                .shadow(color: Color.bloomShadow, radius: 10, x: 4, y: 5)
        }
        .padding(.top, 8)
    }

    private func statusPills(_ viewModel: DashboardViewModel) -> some View {
        HStack(spacing: 8) {
            NavigationLink {
                FinancialWellnessView()
            } label: {
                wellnessPill(viewModel)
            }
            .buttonStyle(.pressable)
            FilterChip(text: "All accounts • \(DateFormatting.monthYear(.now))")
            Spacer()
        }
    }

    private func wellnessPill(_ viewModel: DashboardViewModel) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Palette.emerald)
                .frame(width: 8, height: 8)
                .shadow(color: Palette.emerald.opacity(0.6), radius: 6)
            Text("\(viewModel.wellness.state) • \(viewModel.wellness.score)")
                .font(.appCaption.weight(.heavy))
                .foregroundStyle(Palette.emerald)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            LinearGradient(
                colors: [Palette.emerald.opacity(0.18), Palette.emerald.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: Capsule(style: .continuous)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
        )
    }

    // MARK: - Hero + tiles

    private func monthSummaryTiles(_ viewModel: DashboardViewModel) -> some View {
        HStack(spacing: 10) {
            summaryTile(
                "Safe to spend",
                value: viewModel.safeToSpend,
                color: viewModel.safeToSpend >= 0 ? Palette.income : Palette.expense,
                subtitle: safeToSpendSubtitle(),
                action: { isPresentingBudgetList = true }
            )
            summaryTile(
                "Income",
                value: viewModel.monthIncome,
                color: Palette.income,
                subtitle: DateFormatting.monthYear(.now),
                action: { flowDrilldown = .income }
            )
            summaryTile(
                "Spent",
                value: viewModel.monthSpending,
                color: Palette.peach,
                subtitle: DateFormatting.monthYear(.now),
                action: { flowDrilldown = .expenses }
            )
        }
    }

    @ViewBuilder
    private func summaryTile(_ label: String, value: Decimal, color: Color, subtitle: String, action: (() -> Void)? = nil) -> some View {
        let content = summaryTileCore(label, value: value, color: color, subtitle: subtitle)
        if let action {
            Button(action: action) { content }
                .buttonStyle(.pressable)
        } else {
            content
        }
    }

    private func summaryTileCore(_ label: String, value: Decimal, color: Color, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.appCaption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Text(CurrencyFormatter.string(from: value))
                .font(.appNumber)
                .foregroundStyle(color)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(subtitle)
                .font(.appCaption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Color.appHairline, lineWidth: 1)
        )
        .shadow(color: Color.bloomShadow, radius: 20, x: 7, y: 7)
        .shadow(color: Color.bloomHighlight, radius: 14, x: -6, y: -6)
    }

    private func safeToSpendSubtitle() -> String {
        let calendar = Calendar.current
        let today = calendar.component(.day, from: .now)
        let daysInMonth = calendar.range(of: .day, in: .month, for: .now)?.count ?? 30
        let remaining = max(daysInMonth - today, 1)
        return remaining == 1 ? "1 day" : "\(remaining) days"
    }

    // MARK: - Wellness strip

    /// Phone 1 wellness strip: mini ring, "Thriving 🌿", one-line summary, chevron.
    private func wellnessStrip(_ viewModel: DashboardViewModel) -> some View {
        NavigationLink {
            FinancialWellnessView()
        } label: {
            HStack(spacing: 15) {
                WellnessRing(score: viewModel.wellness.score, size: 66, lineWidth: 8)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(viewModel.wellness.state) \(viewModel.wellness.stateEmoji)")
                        .font(.appTitle3.weight(.heavy))
                        .foregroundStyle(Accent.wellness.deep)
                    Text(viewModel.wellness.summary)
                        .font(.appCaption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Text("›")
                    .font(.appFootnote.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .card()
        }
        .buttonStyle(.pressable)
    }

    // MARK: - Small helpers

    private struct FilterChip: View {
        let text: String
        var body: some View {
            Text(text)
                .font(.appCaption.weight(.heavy))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color.appSurface, in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.appHairline, lineWidth: 1)
                )
                .shadow(color: Color.bloomShadow, radius: 12, x: 3, y: 3)
                .shadow(color: Color.bloomHighlight, radius: 9, x: -3, y: -3)
        }
    }

    /// Shown on days the check-in hasn't been done yet — the ritual only sticks if the app
    /// does the remembering.
    private var checkInCard: some View {
        Button {
            Haptics.tap()
            isPresentingCheckIn = true
        } label: {
            HStack(spacing: 14) {
                BloomRowIcon(emoji: "✅", size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily Check-In")
                        .font(.appHeadline)
                        .foregroundStyle(Color.primary)
                    Text("2 minutes to review today and keep the plan at zero")
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("›")
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
                Text("›")
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
                    BloomRowIcon(emoji: "✨", size: 32)
                    Text("Ask Ledger")
                        .font(.appHeadline)
                        .foregroundStyle(Color.primary)
                    Spacer()
                    Text("›")
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

    /// Phone 1 hero balance card: blob with budget-used percent on the left and the total
    /// balance + monthly delta on the right. Tapping expands the per-account breakdown.
    private func balanceCard(_ viewModel: DashboardViewModel) -> some View {
        Button {
            Haptics.tap()
            isBalanceExpanded.toggle()
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
        .buttonStyle(.pressable)
    }

    /// The month's net change, as a green/coral pill under the balance figure.
    private func deltaPill(_ viewModel: DashboardViewModel) -> some View {
        let up = viewModel.monthNet >= 0
        let color = up ? Palette.income : Palette.expense
        return Text("\(up ? "▲" : "▼") \(CurrencyFormatter.string(from: abs(viewModel.monthNet))) this month")
            .font(.appCaption.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(color.opacity(0.16), in: Capsule())
    }

    /// The per-account rows shown when the balance card is expanded: account icon, name (with its
    /// institution when known), and the account's own balance. Each row edits the account; the
    /// "All accounts" link opens the full list.
    private func accountBreakdown(_ accounts: [Account]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(accounts.enumerated()), id: \.element.persistentModelID) { index, account in
                if index > 0 {
                    Divider().padding(.vertical, 10)
                }
                Button {
                    Haptics.tap()
                    editingAccount = account
                } label: {
                    HStack(spacing: 12) {
                        BloomRowIcon(emoji: account.displayIcon, size: 30)
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
                .buttonStyle(.pressable)
            }
            NavigationLink { AccountListView() } label: {
                HStack {
                    Text("All accounts")
                        .font(.appSubheadline.weight(.semibold))
                    Spacer()
                    Text("›")
                        .font(.appCaption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 14)
            }
            .buttonStyle(.pressable)
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
                summaryTile("Expenses", value: viewModel.monthSpending, color: Palette.peach, icon: "arrow.up.right") { flowDrilldown = .expenses }
                summaryTile("Net", value: viewModel.monthNet, color: viewModel.monthNet < 0 ? Palette.peach : Palette.income, icon: "equal")
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
                    Text("›")
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
                            color: Color(hex: slice.colorHex),
                            category: slice.category
                        )
                    },
                    centerCaption: "Spent",
                    onSelect: { segment in
                        drilldown = segment.category.map(CategoryDrilldown.category) ?? .uncategorized
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
            BloomRowIcon(emoji: ok ? "✅" : "⚠️", size: 44)
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
            Text("›")
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
                DonutSegment(id: "remaining", label: "Remaining", value: remaining, color: Color.secondary.opacity(0.25), isSelectable: false)
            ],
            centerCaption: isOver ? "over budget" : "of budget spent",
            centerValueText: "\(percent)%",
            showLegend: false,
            isInteractive: false
        )
    }

    /// Ember's burn-rate idea, in Bloom: a cool→hot meter with the month's average daily spend.
    /// Tapping opens a sheet with a larger meter and a short explanation.
    private func burnCard(_ viewModel: DashboardViewModel) -> some View {
        Button {
            Haptics.tap()
            isBurnInfoPresented = true
        } label: {
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
                    Text("Cool").font(.appCaption2).foregroundStyle(.secondary)
                    Spacer()
                    Text("you · steady").font(.appCaption2).foregroundStyle(.secondary)
                    Spacer()
                    Text("Hot").font(.appCaption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
        .buttonStyle(.pressable)
    }

    /// A sheet that explains the burn rate with a larger meter.
    private func burnInfoSheet(_ viewModel: DashboardViewModel) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Burn rate")
                            .font(.appHeadline.weight(.heavy))
                        Text("You're averaging \(viewModel.dailyBurnText) so far this month. Keep the marker in the “you · steady” zone and you'll finish the month within budget.")
                            .font(.appBody)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .card()

                    BurnMeter(position: viewModel.burnPosition)
                        .frame(height: 20)
                    HStack {
                        Text("Cool").font(.appCaption2).foregroundStyle(.secondary)
                        Spacer()
                        Text("you · steady").font(.appCaption2).foregroundStyle(.secondary)
                        Spacer()
                        Text("Hot").font(.appCaption2).foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }
                .padding()
            }
            .accentWash(.dashboard)
            .navigationTitle("Burn rate")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// The month's budgets as Bloom clay channels — the dashboard's headline budget view when
    /// per-category budgets exist. Tapping a row drills into that category's transactions; the
    /// "All" button opens the full budget list.
    private func budgetChannelsCard(_ viewModel: DashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeadline("This Month's Budgets") {
                Button {
                    Haptics.tap()
                    isPresentingBudgetList = true
                } label: {
                    Text("All")
                        .font(.appCaption.weight(.heavy))
                        .foregroundStyle(Accent.dashboard.base)
                }
                .buttonStyle(.pressable)
            }
            ForEach(Array(viewModel.budgetRows.enumerated()), id: \.element.id) { index, row in
                Button {
                    Haptics.tap()
                    if let category = row.category {
                        drilldown = .category(category)
                    }
                } label: {
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.pressable)
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
                    emoji: flow == .income ? "💰" : "💸",
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
