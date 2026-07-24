import SwiftUI
import SwiftData

/// The zero-based Budgets tab. A plan card up top shows the month's headline — Left to Assign —
/// with income, assignments, spending, and pace; below it every category budget gets a rich row,
/// and spending that escaped the plan is called out so it can be budgeted in one tap.
struct BudgetListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRefreshCoordinator.self) private var refresh
    @AppStorage("budgetShowBiweekly") private var showBiweekly = false
    @State private var viewModel: BudgetsViewModel?
    @State private var goals: [SavingsGoal] = []
    @State private var activeSheet: ActiveSheet?
    @State private var isConfirmingAutoGenerate = false
    @State private var autoGenerateResult: String?

    /// Converts a monthly amount to the bi-weekly equivalent when the user toggles the budget view.
    private func periodAmount(_ amount: Decimal) -> Decimal {
        showBiweekly ? amount / 2 : amount
    }

    /// Formats an amount for the currently selected budget period.
    private func periodMoney(_ amount: Decimal) -> String {
        CurrencyFormatter.string(from: periodAmount(amount))
    }

    /// Suffix for the current budget period view.
    private var periodSuffix: String {
        showBiweekly ? " /bi-weekly" : " /mo"
    }

    /// One source of truth for the several sheets this screen can present. Consolidating the
    /// previous six independent `.sheet` bindings behind a single `.sheet(item:)` removes the
    /// stacked-sheet footgun: only one sheet can present at a time, and two flags flipping in the
    /// same runloop tick could drop a presentation or leave a flag stuck true.
    private enum ActiveSheet: Identifiable {
        case suggestion
        case newBudget
        case editRow(BudgetsViewModel.BudgetRow)
        case quickBudget(Category)
        case income
        case newGoal
        case editGoal(SavingsGoal?)
        case askLedger

        var id: String {
            switch self {
            case .suggestion: "suggestion"
            case .newBudget: "newBudget"
            case .editRow(let row): "editRow-\(row.id.hashValue)"
            case .quickBudget(let category): "quickBudget-\(category.persistentModelID.hashValue)"
            case .income: "income"
            case .newGoal: "newGoal"
            case .editGoal(let goal): "editGoal-\(goal?.persistentModelID.hashValue ?? 0)"
            case .askLedger: "askLedger"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                            headerRow(viewModel)
                            if viewModel.rows.isEmpty {
                                emptyPlanCard
                            } else {
                                planCard(viewModel)
                                categoriesCard(viewModel)
                                if !viewModel.unbudgeted.isEmpty {
                                    offPlanCard(viewModel)
                                }
                            }
                            goalsCard(viewModel)
                            aiInsightCard(viewModel)
                        }
                        .padding()
                    }
                    .refreshable { await refresh.refresh(container: modelContext.container) }

                } else {
                    LoadingView()
                }
            }
            .navigationTitle("Budgets & goals")
            .accentWash(.budgets)
            .accent(.budgets)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Picker("Budget period", selection: $showBiweekly) {
                        Text("Monthly").tag(false)
                        Text("Bi-weekly").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { activeSheet = .newBudget } label: {
                            Label { Text("Add Budget") } icon: { Text("➕") }
                        }
                        Button { activeSheet = .newGoal } label: {
                            Label { Text("Add Goal") } icon: { Text("🎯") }
                        }
                        Button { activeSheet = .income } label: {
                            Label { Text("Set Monthly Income") } icon: { Text("💰") }
                        }
                        Button { activeSheet = .suggestion } label: {
                            Label { Text("Suggest a Budget") } icon: { Text("✨") }
                        }
                        Button { isConfirmingAutoGenerate = true } label: {
                            Label { Text("Auto-Generate from Last 3 Months") } icon: { Text("🪄") }
                        }
                    } label: {
                        Text("➕")
                    }
                    .accessibilityLabel("Add to budget plan")
                }
            }
            .confirmationDialog(
                "Create budgets for \(DateFormatting.monthYear(viewModel?.selectedMonth ?? .now)) from your average spending over the last 3 months?",
                isPresented: $isConfirmingAutoGenerate,
                titleVisibility: .visible
            ) {
                Button("Auto-Generate") {
                    let created = viewModel?.generateFromRecentHistory() ?? 0
                    autoGenerateResult = created > 0
                        ? "Set \(created) budget\(created == 1 ? "" : "s") from recent spending."
                        : "No spending found in the last 3 months to build a budget from."
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Existing budgets for this month will be updated to match.")
            }
            .alert("Budget", isPresented: Binding(get: { autoGenerateResult != nil }, set: { if !$0 { autoGenerateResult = nil } })) {
                Button("OK", role: .cancel) { autoGenerateResult = nil }
            } message: {
                Text(autoGenerateResult ?? "")
            }
            // A single sheet presenter for every sheet this screen shows. Reloading on dismiss keeps
            // the plan in sync no matter which sheet closed — including the advisor, which can apply
            // budgets of its own; income edits already reload via `setIncomeOverride`, so the extra
            // reload there is a harmless no-op.
            .sheet(item: $activeSheet, onDismiss: {
                viewModel?.load()
                loadGoals()
            }) { sheet in
                if let viewModel {
                    switch sheet {
                    case .suggestion:
                        BudgetSuggestionView(month: viewModel.selectedMonth)
                    case .newBudget:
                        BudgetEditView(month: viewModel.selectedMonth, budgetRow: nil)
                    case .editRow(let row):
                        BudgetEditView(month: viewModel.selectedMonth, budgetRow: row)
                    case .quickBudget(let category):
                        BudgetEditView(month: viewModel.selectedMonth, budgetRow: nil, preselectedCategory: category)
                    case .income:
                        BudgetIncomeEditView(
                            month: viewModel.selectedMonth,
                            actualIncome: viewModel.actualIncome,
                            currentOverride: viewModel.incomeOverride
                        ) { amount in
                            viewModel.setIncomeOverride(amount)
                        }
                    case .newGoal:
                        SavingsGoalEditView(goal: nil)
                    case .editGoal(let goal):
                        SavingsGoalEditView(goal: goal)
                    case .askLedger:
                        AskLedgerView(month: viewModel.selectedMonth)
                    }
                }
            }
            .task {
                if viewModel == nil { viewModel = BudgetsViewModel(modelContext: modelContext) }
                viewModel?.load()
                loadGoals()
            }
            // Reload once a background refresh (sync + categorize) finishes, so spent amounts
            // reflect freshly imported transactions without re-opening the tab.
            .onChange(of: refresh.refreshCount) { _, _ in
                viewModel?.load()
                loadGoals()
            }
        }
    }

    // MARK: - Plan card

    private func planCard(_ viewModel: BudgetsViewModel) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text("LEFT TO ASSIGN")
                    .font(.appCaption.weight(.heavy))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(periodMoney(viewModel.leftToAssign))
                        .font(AppFont.scaled(34, relativeTo: .largeTitle, weight: .heavy))
                        .foregroundStyle(leftToAssignColor(viewModel))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(periodSuffix)
                        .font(.appCaption2)
                        .foregroundStyle(.secondary)
                }
                planStatusChip(viewModel)
            }

            Divider()

            HStack(spacing: 12) {
                Button { activeSheet = .income } label: {
                    planTile(
                        label: viewModel.incomeOverride == nil ? "Income · actual" : "Income · planned",
                        value: viewModel.incomeToAssign,
                        color: Palette.income,
                        showsChevron: true
                    )
                }
                .buttonStyle(.pressable)
                planTile(label: "Assigned", value: viewModel.totalAllocated, color: .primary)
                planTile(label: "Spent", value: viewModel.totalSpent + viewModel.totalUnbudgetedSpent, color: Palette.expense)
            }

            if viewModel.totalAvailable > 0 || viewModel.totalSpent > 0 {
                VStack(spacing: 6) {
                    BudgetProgressBar(
                        progress: viewModel.overallProgress,
                        isOverBudget: viewModel.isOverallOverBudget,
                        paceMarker: paceMarker(viewModel)
                    )
                    HStack {
                        Text("\(periodMoney(viewModel.totalSpent)) of \(periodMoney(viewModel.totalAvailable))\(periodSuffix) budget spent")
                        Spacer()
                        if let daysRemaining = viewModel.daysRemaining {
                            Text("\(daysRemaining) day\(daysRemaining == 1 ? "" : "s") left")
                        } else if viewModel.monthProgress >= 1 {
                            Text("Month complete")
                        }
                    }
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .card()
        .padding(.top, 4)
    }

    private func leftToAssignColor(_ viewModel: BudgetsViewModel) -> Color {
        if viewModel.leftToAssign < 0 { return Palette.expense }
        if viewModel.leftToAssign == 0 && viewModel.incomeToAssign > 0 { return .brandEmerald }
        return .primary
    }

    @ViewBuilder
    private func planStatusChip(_ viewModel: BudgetsViewModel) -> some View {
        let (text, icon, color): (String, String, Color) = {
            if viewModel.incomeToAssign <= 0 && viewModel.totalAllocated <= 0 {
                return ("Set your income to start the plan", "ℹ️", .secondary)
            }
            if viewModel.leftToAssign < 0 {
                return ("Over-assigned by \(periodMoney(0 - viewModel.leftToAssign))\(periodSuffix)", "⚠️", Palette.expense)
            }
            if viewModel.leftToAssign == 0 {
                return ("Every dollar has a job", "✅", .brandEmerald)
            }
            return ("Assign \(periodMoney(viewModel.leftToAssign))\(periodSuffix) to finish the plan", "⬇️", Palette.amber)
        }()

        Label {
            Text(text).font(.appCaption.weight(.semibold)).foregroundStyle(color)
        } icon: {
            Text(icon)
        }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.18), in: Capsule())
    }

    private func planTile(label: String, value: Decimal, color: Color, showsChevron: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Text(label)
                if showsChevron {
                    Text("✎")
                        .font(.appCaption2.weight(.bold))
                }
            }
            .font(.appCaption2)
            .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(periodMoney(value))
                    .font(.appSubheadline.weight(.semibold))
                    .foregroundStyle(color)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(periodSuffix)
                    .font(.appCaption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Show the pace tick only for the current month — a fully past or future month has no
    /// meaningful "you are here".
    private func paceMarker(_ viewModel: BudgetsViewModel) -> Double? {
        viewModel.monthProgress > 0 && viewModel.monthProgress < 1 ? viewModel.monthProgress : nil
    }

    private func monthPicker(_ viewModel: BudgetsViewModel) -> some View {
        HStack {
            monthChevron("‹") { shiftMonth(viewModel, by: -1) }
            Spacer()
            Text(DateFormatting.monthYear(viewModel.selectedMonth))
                .font(.appHeadline)
            Spacer()
            monthChevron("›") { shiftMonth(viewModel, by: 1) }
        }
    }

    /// A 44pt hit area — the bare chevron glyph is far too small a tap target on its own.
    private func monthChevron(_ glyph: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(.appBody.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        // The plan card is a List row with several buttons (both chevrons + the income tile).
        // Without an explicit style the row treats them as one tap target, so a chevron tap fires
        // ambiguously and the month never changes. `.plain` makes each its own tap target.
        .buttonStyle(.plain)
    }

    private func shiftMonth(_ viewModel: BudgetsViewModel, by value: Int) {
        if let newMonth = Calendar.current.date(byAdding: .month, value: value, to: viewModel.selectedMonth) {
            viewModel.selectedMonth = Budget.normalize(newMonth)
        }
    }

    private func loadGoals() {
        let descriptor = FetchDescriptor<SavingsGoal>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        goals = (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Header + month chip

    private func headerRow(_ viewModel: BudgetsViewModel) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Budgets & goals")
                .font(.appHeadline.weight(.heavy))
            Spacer()
            monthChip(viewModel)
        }
    }

    /// A compact month selector styled as a Bloom chip, matching the rendering's "July ▾".
    private func monthChip(_ viewModel: BudgetsViewModel) -> some View {
        Menu {
            ForEach(-6..<7, id: \.self) { offset in
                let month = Calendar.current.date(byAdding: .month, value: offset, to: .now) ?? .now
                let normalized = Budget.normalize(month)
                Button(DateFormatting.monthYear(normalized)) {
                    viewModel.selectedMonth = normalized
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(monthLabel(viewModel.selectedMonth))
                    .font(.appCaption.weight(.bold))
                Text("▾")
                    .font(.appCaption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.appSurface, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.appHairline, lineWidth: 1)
            )
        }
        .buttonStyle(.pressable)
    }

    private func monthLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_CA")
        formatter.setLocalizedDateFormatFromTemplate("MMMM")
        return formatter.string(from: date)
    }

    // MARK: - Category budgets card

    private func categoriesCard(_ viewModel: BudgetsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Categories")
                    .font(.appCaption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Spacer()
                if viewModel.overBudgetCount > 0 {
                    Text("\(viewModel.overBudgetCount) over")
                        .font(.appCaption2.weight(.bold))
                        .foregroundStyle(Palette.expense)
                }
            }
            VStack(spacing: 0) {
                ForEach(viewModel.rows) { row in
                    categoryBudgetRow(row, viewModel: viewModel)
                    if row.id != viewModel.rows.last?.id {
                        BudgetsDivider()
                    }
                }
            }
            if viewModel.totalRollover > 0 {
                Text("Includes \(periodMoney(viewModel.totalRollover))\(periodSuffix) rolled over from last month.")
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .card()
    }

    @ViewBuilder
    private func categoryBudgetRow(_ row: BudgetsViewModel.BudgetRow, viewModel: BudgetsViewModel) -> some View {
        if row.hasCategory {
            NavigationLink {
                if let category = row.budget.category {
                    CategoryTransactionsView(category: category, month: viewModel.selectedMonth)
                }
            } label: {
                BudgetRowView(row: row, paceMarker: paceMarker(viewModel), showBiweekly: showBiweekly)
            }
            .buttonStyle(.pressable)
            .contextMenu {
                Button { activeSheet = .editRow(row) } label: { Label("Edit Budget", systemImage: "pencil") }
                Button(role: .destructive) { viewModel.delete(row) } label: { Label("Delete Budget", systemImage: "trash") }
            }
        } else {
            BudgetRowView(row: row, paceMarker: paceMarker(viewModel), showBiweekly: showBiweekly)
                .contextMenu {
                    Button { activeSheet = .editRow(row) } label: { Label("Edit Budget", systemImage: "pencil") }
                    Button(role: .destructive) { viewModel.delete(row) } label: { Label("Delete Budget", systemImage: "trash") }
                }
        }
    }

    // MARK: - Off-plan spending card

    private func offPlanCard(_ viewModel: BudgetsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Off-Plan Spending")
                .font(.appCaption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(viewModel.unbudgeted) { item in
                    offPlanRow(item)
                    if item.id != viewModel.unbudgeted.last?.id {
                        BudgetsDivider()
                    }
                }
            }
            Text("Money spent outside the plan this month. Give it a budget so every dollar has a job.")
                .font(.appCaption)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    @ViewBuilder
    private func offPlanRow(_ item: BudgetsViewModel.UnbudgetedRow) -> some View {
        if item.hasCategory {
            Button {
                if let category = item.category { activeSheet = .quickBudget(category) }
            } label: {
                UnbudgetedRowView(
                    name: item.categoryName,
                    detail: "Tap to set a budget",
                    spent: item.spent,
                    showBiweekly: showBiweekly
                )
            }
            .buttonStyle(.pressable)
        } else {
            UnbudgetedRowView(
                name: "Uncategorized",
                detail: "Categorize these transactions to budget them",
                spent: item.spent,
                showBiweekly: showBiweekly
            )
        }
    }

    // MARK: - Savings goals card

    private func goalsCard(_ viewModel: BudgetsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Savings goals")
                    .font(.appCaption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { activeSheet = .newGoal } label: {
                    Text("Add")
                        .font(.appCaption.weight(.heavy))
                        .foregroundStyle(Accent.wellness.deep)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Accent.wellness.soft, in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
            }
            if goals.isEmpty {
                Text("No goals yet. Add one to keep your big purchases on track.")
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(goals) { goal in
                        goalRow(goal)
                            .contentShape(Rectangle())
                            .onTapGesture { activeSheet = .editGoal(goal) }
                            .contextMenu {
                                Button { activeSheet = .editGoal(goal) } label: { Label("Edit", systemImage: "pencil") }
                                Button(role: .destructive) {
                                    modelContext.delete(goal)
                                    try? modelContext.save()
                                    loadGoals()
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                        if goal.persistentModelID != goals.last?.persistentModelID {
                            BudgetsDivider()
                        }
                    }
                }
            }
        }
        .card()
    }

    private func goalRow(_ goal: SavingsGoal) -> some View {
        HStack(spacing: 14) {
            GoalPot(progress: goal.progress, emoji: goalEmoji(for: goal))
            VStack(alignment: .leading, spacing: 4) {
                Text(goal.name)
                    .font(.appSubheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(CurrencyFormatter.string(from: goal.savedAmount)) of \(CurrencyFormatter.string(from: goal.targetAmount))")
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if let monthly = goal.requiredMonthlyContribution {
                    Text("\(CurrencyFormatter.string(from: monthly))/mo to stay on track")
                        .font(.appCaption2)
                        .foregroundStyle(Palette.emerald)
                }
            }
            Spacer(minLength: 8)
            Text("\(Int(goal.progress * 100))%")
                .font(.appCaption.weight(.heavy))
                .foregroundStyle(Accent.wellness.deep)
        }
        .padding(.vertical, 6)
    }

    private func goalEmoji(for goal: SavingsGoal) -> String {
        if goal.isComplete { return "🏆" }
        if goal.progress > 0.5 { return "🌳" }
        if goal.progress > 0.15 { return "🌿" }
        return "🌱"
    }

    // MARK: - AI insight card

    private func aiInsightCard(_ viewModel: BudgetsViewModel) -> some View {
        let message = aiMessage(for: viewModel)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                BloomRowIcon(emoji: "✨", size: 30)
                Text("Ask Ledger")
                    .font(.appHeadline)
                    .foregroundStyle(Accent.insights.deep)
                Spacer()
            }
            Text(message)
                .font(.appBody)
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                activeSheet = .askLedger
            } label: {
                HStack {
                    Spacer()
                    Text("Rebalance")
                        .font(.appCaption.weight(.heavy))
                        .foregroundStyle(Color.white)
                    Spacer()
                }
                .padding(.vertical, 12)
                .background(Accent.insights.base, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .padding(Theme.cardPadding)
        .background(
            LinearGradient(
                colors: [Accent.insights.base.opacity(0.12), Color.appSurface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Accent.insights.base.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: Color.bloomShadow, radius: 20, x: 7, y: 7)
        .shadow(color: Color.bloomHighlight, radius: 14, x: -6, y: -6)
    }

    private func aiMessage(for viewModel: BudgetsViewModel) -> String {
        if let over = viewModel.rows.first(where: { $0.isOverBudget }) {
            let available = viewModel.rows.first { !$0.isOverBudget && $0.remaining > 0 }
            if let available {
                return "\(over.categoryName) is \(CurrencyFormatter.string(from: over.remaining * -1)) over. Pull it from \(available.categoryName) so nothing turns red."
            }
            return "\(over.categoryName) is \(CurrencyFormatter.string(from: over.remaining * -1)) over this month."
        }
        if viewModel.leftToAssign > 0 {
            return "You have \(CurrencyFormatter.string(from: viewModel.leftToAssign)) left to assign this month."
        }
        return "Your budget plan is on track. Ask me anything about your money."
    }

    // MARK: - Empty state

    private var emptyPlanCard: some View {
        VStack(spacing: 14) {
            BloomRowIcon(emoji: "📊", size: 64)
            Text("No Budgets Yet")
                .font(.appTitle3.weight(.heavy))
            Text("Assign your income to categories until Left to Assign hits zero. Start from scratch, or build the plan from your recent spending.")
                .font(.appSubheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button {
                    activeSheet = .suggestion
                } label: {
                    Label("Suggest a Budget", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                Button {
                    activeSheet = .newBudget
                } label: {
                    Label("Add Budget", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .card()
    }
}

// MARK: - Rows

private struct BudgetRowView: View {
    let row: BudgetsViewModel.BudgetRow
    var paceMarker: Double?
    var showBiweekly: Bool = false

    private func periodMoney(_ amount: Decimal) -> String {
        CurrencyFormatter.string(from: showBiweekly ? amount / 2 : amount)
    }

    private var periodSuffix: String {
        showBiweekly ? " /bi-weekly" : " /mo"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            BloomRowIcon(emoji: BloomEmoji.categoryEmoji(name: row.categoryName), size: 40)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    // A long category name truncates instead of wrapping and pushing the
                    // remaining pill onto a second line.
                    Text(row.categoryName)
                        .font(.appSubheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    remainingPill
                }
                BudgetProgressBar(progress: row.progress, isOverBudget: row.isOverBudget, paceMarker: paceMarker)
                HStack {
                    Text(detailText)
                    Spacer()
                    if let percentUsed = row.percentUsed {
                        Text("\(percentUsed)%")
                            .foregroundStyle(row.isOverBudget ? Palette.expense : .secondary)
                    }
                }
                .font(.appCaption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private var remainingPill: some View {
        Text(row.isOverBudget
             ? "\(periodMoney(0 - row.remaining))\(periodSuffix) over"
             : "\(periodMoney(row.remaining))\(periodSuffix) left")
            .font(.appCaption.weight(.bold))
            .foregroundStyle(row.isOverBudget ? Palette.expense : Palette.income)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background((row.isOverBudget ? Palette.expense : Palette.income).opacity(0.22), in: Capsule())
            .layoutPriority(1)
    }

    private var detailText: String {
        var text = "\(periodMoney(row.spent)) of \(periodMoney(row.allocatedIncludingRollover))\(periodSuffix)"
        if row.rolloverFromPreviousMonth > 0 {
            text += " · incl. \(periodMoney(row.rolloverFromPreviousMonth)) rollover"
        }
        return text
    }
}

private struct UnbudgetedRowView: View {
    let name: String
    let detail: String
    let spent: Decimal
    var showBiweekly: Bool = false

    private var emoji: String {
        name.lowercased() == "uncategorized" ? "❓" : BloomEmoji.categoryEmoji(name: name)
    }

    private func periodMoney(_ amount: Decimal) -> String {
        CurrencyFormatter.string(from: showBiweekly ? amount / 2 : amount)
    }

    private var periodSuffix: String {
        showBiweekly ? " /bi-weekly" : " /mo"
    }

    var body: some View {
        HStack(spacing: 12) {
            BloomRowIcon(emoji: emoji, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.appSubheadline.weight(.semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(periodMoney(spent))
                    .font(.appBody.weight(.heavy))
                    .foregroundStyle(Palette.amber)
                    .layoutPriority(1)
                Text(periodSuffix)
                    .font(.appCaption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

private struct BudgetsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.appHairline)
            .frame(height: 1)
            .padding(.leading, 54)
    }
}

private struct GoalPot: View {
    let progress: Double
    let emoji: String
    private let size: CGFloat = 48

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.ink3.opacity(0.22))
            Circle()
                .trim(from: 0, to: max(min(progress, 1), 0))
                .stroke(
                    Accent.wellness.base,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(4)
            Circle()
                .fill(Color.appSurface)
                .frame(width: size - 16, height: size - 16)
            Text(emoji)
                .font(.system(size: 20))
        }
        .frame(width: size, height: size)
        .shadow(color: Color.bloomShadow, radius: 8, x: 3, y: 3)
        .shadow(color: Color.bloomHighlight, radius: 6, x: -3, y: -3)
    }
}

#Preview {
    BudgetListView()
        .modelContainer(for: LedgerSchema.models, inMemory: true)
        .environment(AppRefreshCoordinator())
}
