import SwiftUI
import SwiftData

/// The zero-based Budgets tab. A plan card up top shows the month's headline — Left to Assign —
/// with income, assignments, spending, and pace; below it every category budget gets a rich row,
/// and spending that escaped the plan is called out so it can be budgeted in one tap.
struct BudgetListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRefreshCoordinator.self) private var refresh
    @State private var viewModel: BudgetsViewModel?
    @State private var activeSheet: ActiveSheet?
    @State private var isConfirmingAutoGenerate = false
    @State private var autoGenerateResult: String?

    /// One source of truth for the several sheets this screen can present. Consolidating the
    /// previous six independent `.sheet` bindings behind a single `.sheet(item:)` removes the
    /// stacked-sheet footgun: only one sheet can present at a time, and two flags flipping in the
    /// same runloop tick could drop a presentation or leave a flag stuck true.
    private enum ActiveSheet: Identifiable {
        case suggestion
        case advisor
        case newBudget
        case editRow(BudgetsViewModel.BudgetRow)
        case quickBudget(Category)
        case income

        var id: String {
            switch self {
            case .suggestion: "suggestion"
            case .advisor: "advisor"
            case .newBudget: "newBudget"
            case .editRow(let row): "editRow-\(row.id.hashValue)"
            case .quickBudget(let category): "quickBudget-\(category.persistentModelID.hashValue)"
            case .income: "income"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    List {
                        Section {
                            planCard(viewModel)
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                        if viewModel.rows.isEmpty {
                            Section {
                                emptyPlanCard
                            }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        } else {
                            budgetsSection(viewModel)
                        }

                        if !viewModel.unbudgeted.isEmpty {
                            unbudgetedSection(viewModel)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    // Pull-to-refresh runs a real sync; the refreshCount observer below
                    // then reloads the rows with the new spent amounts.
                    .refreshable { await refresh.refresh(container: modelContext.container) }
                    // Floating AI financial-advisor bubble, tucked in the bottom-trailing corner
                    // above the tab bar.
                    .overlay(alignment: .bottomTrailing) { advisorBubble }
                } else {
                    LoadingView()
                }
            }
            .navigationTitle("Budgets")
            .accentWash(.budgets)
            .accent(.budgets)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { activeSheet = .newBudget } label: {
                            Label("Add Budget", systemImage: "plus")
                        }
                        Button { activeSheet = .income } label: {
                            Label("Set Monthly Income", systemImage: "dollarsign.circle")
                        }
                        Button { activeSheet = .suggestion } label: {
                            Label("Suggest a Budget", systemImage: "sparkles")
                        }
                        Button { isConfirmingAutoGenerate = true } label: {
                            Label("Auto-Generate from Last 3 Months", systemImage: "wand.and.stars")
                        }
                    } label: {
                        Image(systemName: "plus")
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
            .sheet(item: $activeSheet, onDismiss: { viewModel?.load() }) { sheet in
                if let viewModel {
                    switch sheet {
                    case .suggestion:
                        BudgetSuggestionView(month: viewModel.selectedMonth)
                    case .advisor:
                        AIAdvisorView(month: viewModel.selectedMonth)
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
                    }
                }
            }
            .task {
                if viewModel == nil { viewModel = BudgetsViewModel(modelContext: modelContext) }
                viewModel?.load()
            }
            // Reload once a background refresh (sync + categorize) finishes, so spent amounts
            // reflect freshly imported transactions without re-opening the tab.
            .onChange(of: refresh.refreshCount) { _, _ in viewModel?.load() }
        }
    }

    // MARK: - Advisor

    private var advisorBubble: some View {
        Button {
            Haptics.tap()
            activeSheet = .advisor
        } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(Accent.insights.gradient, in: Circle())
                .shadow(color: Accent.insights.base.opacity(0.5), radius: 12, y: 6)
        }
        .buttonStyle(.pressable)
        .padding(.trailing, 20)
        .padding(.bottom, 20)
        .accessibilityLabel("Financial advisor")
    }

    // MARK: - Plan card

    private func planCard(_ viewModel: BudgetsViewModel) -> some View {
        VStack(spacing: 16) {
            monthPicker(viewModel)

            VStack(spacing: 8) {
                Text("LEFT TO ASSIGN")
                    .font(.appCaption.weight(.heavy))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Text(CurrencyFormatter.string(from: viewModel.leftToAssign))
                    .font(.appDisplay)
                    .foregroundStyle(leftToAssignColor(viewModel))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                planStatusChip(viewModel)
            }

            Divider()

            HStack(spacing: 12) {
                Button { activeSheet = .income } label: {
                    planTile(
                        label: viewModel.incomeOverride == nil ? "Income · actual" : "Income · planned",
                        value: viewModel.incomeToAssign,
                        color: .green,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
                planTile(label: "Assigned", value: viewModel.totalAllocated, color: .primary)
                planTile(label: "Spent", value: viewModel.totalSpent + viewModel.totalUnbudgetedSpent, color: .red)
            }

            if viewModel.totalAvailable > 0 || viewModel.totalSpent > 0 {
                VStack(spacing: 6) {
                    BudgetProgressBar(
                        progress: viewModel.overallProgress,
                        isOverBudget: viewModel.isOverallOverBudget,
                        paceMarker: paceMarker(viewModel)
                    )
                    HStack {
                        Text("\(CurrencyFormatter.string(from: viewModel.totalSpent)) of \(CurrencyFormatter.string(from: viewModel.totalAvailable)) budget spent")
                        Spacer()
                        if let daysRemaining = viewModel.daysRemaining {
                            Text("\(daysRemaining) day\(daysRemaining == 1 ? "" : "s") left")
                        } else if viewModel.monthProgress >= 1 {
                            Text("Month complete")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.top, 4)
    }

    private func leftToAssignColor(_ viewModel: BudgetsViewModel) -> Color {
        if viewModel.leftToAssign < 0 { return .red }
        if viewModel.leftToAssign == 0 && viewModel.incomeToAssign > 0 { return .brandEmerald }
        return .primary
    }

    @ViewBuilder
    private func planStatusChip(_ viewModel: BudgetsViewModel) -> some View {
        let (text, symbol, color): (String, String, Color) = {
            if viewModel.incomeToAssign <= 0 && viewModel.totalAllocated <= 0 {
                return ("Set your income to start the plan", "info.circle.fill", .secondary)
            }
            if viewModel.leftToAssign < 0 {
                return ("Over-assigned by \(CurrencyFormatter.string(from: -viewModel.leftToAssign))", "exclamationmark.triangle.fill", .red)
            }
            if viewModel.leftToAssign == 0 {
                return ("Every dollar has a job", "checkmark.seal.fill", .brandEmerald)
            }
            return ("Assign \(CurrencyFormatter.string(from: viewModel.leftToAssign)) to finish the plan", "arrow.down.circle.fill", .orange)
        }()

        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.18), in: Capsule())
    }

    private func planTile(label: String, value: Decimal, color: Color, showsChevron: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Text(label)
                if showsChevron {
                    Image(systemName: "pencil")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            Text(CurrencyFormatter.string(from: value))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
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
            monthChevron("chevron.left") { shiftMonth(viewModel, by: -1) }
            Spacer()
            Text(DateFormatting.monthYear(viewModel.selectedMonth))
                .font(.headline)
            Spacer()
            monthChevron("chevron.right") { shiftMonth(viewModel, by: 1) }
        }
    }

    /// A 44pt hit area — the bare chevron glyph is far too small a tap target on its own.
    private func monthChevron(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
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

    // MARK: - Budgets section

    @ViewBuilder
    private func budgetsSection(_ viewModel: BudgetsViewModel) -> some View {
        Section {
            ForEach(viewModel.rows) { row in
                budgetRow(row, viewModel: viewModel)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            UINotificationFeedbackGenerator().notificationOccurred(.warning)
                            viewModel.delete(row)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            activeSheet = .editRow(row)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.accentColor)
                    }
                    // Long-press menu, so editing/deleting a budget stays reachable
                    // even where the paged tab swipe competes with row swipes.
                    .contextMenu {
                        Button {
                            activeSheet = .editRow(row)
                        } label: {
                            Label("Edit Budget", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            UINotificationFeedbackGenerator().notificationOccurred(.warning)
                            viewModel.delete(row)
                        } label: {
                            Label("Delete Budget", systemImage: "trash")
                        }
                    }
            }
        } header: {
            HStack {
                Text("Category Budgets")
                Spacer()
                if viewModel.overBudgetCount > 0 {
                    Text("\(viewModel.overBudgetCount) over")
                        .foregroundStyle(.red)
                }
            }
        } footer: {
            if viewModel.totalRollover > 0 {
                Text("Includes \(CurrencyFormatter.string(from: viewModel.totalRollover)) rolled over from last month.")
            }
        }
    }

    @ViewBuilder
    private func budgetRow(_ row: BudgetsViewModel.BudgetRow, viewModel: BudgetsViewModel) -> some View {
        if row.hasCategory {
            NavigationLink {
                // The live category is faulted here, on tap, rather than during every list render.
                if let category = row.budget.category {
                    CategoryTransactionsView(category: category, month: viewModel.selectedMonth)
                }
            } label: {
                BudgetRowView(row: row, paceMarker: paceMarker(viewModel))
            }
        } else {
            BudgetRowView(row: row, paceMarker: paceMarker(viewModel))
        }
    }

    // MARK: - Unbudgeted section

    private func unbudgetedSection(_ viewModel: BudgetsViewModel) -> some View {
        Section {
            ForEach(viewModel.unbudgeted) { item in
                if item.hasCategory {
                    Button {
                        // Faulted on tap, not during render.
                        if let category = item.category { activeSheet = .quickBudget(category) }
                    } label: {
                        UnbudgetedRowView(
                            symbol: item.categorySymbolName,
                            color: item.categoryColorHex.map { Color(hex: $0) } ?? .gray,
                            name: item.categoryName,
                            detail: "Tap to set a budget",
                            spent: item.spent
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    UnbudgetedRowView(
                        symbol: "questionmark",
                        color: .gray,
                        name: "Uncategorized",
                        detail: "Categorize these transactions to budget them",
                        spent: item.spent
                    )
                }
            }
        } header: {
            Text("Off-Plan Spending")
        } footer: {
            Text("Money spent outside the plan this month. Give it a budget so every dollar has a job.")
        }
    }

    // MARK: - Empty state

    private var emptyPlanCard: some View {
        VStack(spacing: 14) {
            IconBadge(systemName: "chart.pie.fill", accent: .budgets, size: 64)
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
        .padding(.vertical, 28)
        .padding(.horizontal)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Rows

private struct BudgetRowView: View {
    let row: BudgetsViewModel.BudgetRow
    var paceMarker: Double?

    private var categoryColor: Color {
        row.categoryColorHex.map { Color(hex: $0) } ?? Palette.indigo
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: row.categorySymbolName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(
                    LinearGradient(colors: [categoryColor, categoryColor.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .accessibilityHidden(true)

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
                            .foregroundStyle(row.isOverBudget ? .red : .secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private var remainingPill: some View {
        Text(row.isOverBudget
             ? "\(CurrencyFormatter.string(from: -row.remaining)) over"
             : "\(CurrencyFormatter.string(from: row.remaining)) left")
            .font(.caption.weight(.bold))
            .foregroundStyle(row.isOverBudget ? Palette.expense : Palette.income)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background((row.isOverBudget ? Palette.expense : Palette.income).opacity(0.22), in: Capsule())
            .layoutPriority(1)
    }

    private var detailText: String {
        var text = "\(CurrencyFormatter.string(from: row.spent)) of \(CurrencyFormatter.string(from: row.allocatedIncludingRollover))"
        if row.rolloverFromPreviousMonth > 0 {
            text += " · incl. \(CurrencyFormatter.string(from: row.rolloverFromPreviousMonth)) rollover"
        }
        return text
    }
}

private struct UnbudgetedRowView: View {
    let symbol: String
    let color: Color
    let name: String
    let detail: String
    let spent: Decimal

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(
                    LinearGradient(colors: [color, color.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.appSubheadline.weight(.semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(CurrencyFormatter.string(from: spent))
                .font(.appBody.weight(.heavy))
                .foregroundStyle(Palette.amber)
                .layoutPriority(1)
        }
        .padding(.vertical, 5)
    }
}

#Preview {
    BudgetListView()
        .modelContainer(for: LedgerSchema.models, inMemory: true)
        .environment(AppRefreshCoordinator())
}
