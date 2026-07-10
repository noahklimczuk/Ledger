import Charts
import SwiftUI
import SwiftData

struct ReportsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: ReportsViewModel?
    /// Name of the category whose transactions are expanded in the category card, if any.
    @State private var expandedCategory: String?

    var body: some View {
        Group {
            if let viewModel {
                ScrollView {
                    VStack(spacing: 20) {
                        rangePicker(viewModel)
                        if viewModel.hasData {
                            summaryCards(viewModel)
                            netWorthCard(viewModel)
                            categoryCard(viewModel)
                            incomeExpenseCard(viewModel)
                            monthOverMonthCard(viewModel)
                        } else {
                            EmptyStateView(
                                systemImage: "chart.bar.xaxis",
                                title: "No Data in This Range",
                                message: "Add transactions or pick a wider date range to see your spending reports."
                            )
                            .frame(minHeight: 240)
                        }
                    }
                    .padding()
                }
            } else {
                LoadingView()
            }
        }
        .navigationTitle("Reports")
        .task {
            if viewModel == nil { viewModel = ReportsViewModel(modelContext: modelContext) }
            viewModel?.load()
        }
    }

    // MARK: - Range

    @ViewBuilder
    private func rangePicker(_ viewModel: ReportsViewModel) -> some View {
        VStack(spacing: 12) {
            Picker("Range", selection: Binding(get: { viewModel.range }, set: { viewModel.range = $0 })) {
                ForEach(ReportDateRange.allCases) { range in
                    Text(range.displayName).tag(range)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)

            if viewModel.range == .custom {
                DatePicker("From", selection: Binding(get: { viewModel.customStart }, set: { viewModel.customStart = $0 }), displayedComponents: .date)
                DatePicker("To", selection: Binding(get: { viewModel.customEnd }, set: { viewModel.customEnd = $0 }), displayedComponents: .date)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Summary

    private func summaryCards(_ viewModel: ReportsViewModel) -> some View {
        HStack(spacing: 12) {
            summaryTile("Income", value: viewModel.totalIncome, color: .green)
            summaryTile("Expenses", value: viewModel.totalExpense, color: .red)
            summaryTile("Net", value: viewModel.net, color: viewModel.net < 0 ? .red : .primary)
        }
    }

    private func summaryTile(_ label: String, value: Decimal, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(CurrencyFormatter.string(from: value))
                .font(.headline)
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Net worth

    @ViewBuilder
    private func netWorthCard(_ viewModel: ReportsViewModel) -> some View {
        card(title: "Net Worth") {
            Chart(viewModel.netWorthPoints) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("Net worth", point.value.doubleValue)
                )
                .foregroundStyle(LinearGradient(colors: [.accentColor.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))

                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Net worth", point.value.doubleValue)
                )
                .foregroundStyle(.tint)
                .interpolationMethod(.catmullRom)
            }
            .frame(height: 200)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Net worth over time")
            .accessibilityValue(netWorthAccessibilitySummary(viewModel))
        }
    }

    // MARK: - Category spending

    @ViewBuilder
    private func categoryCard(_ viewModel: ReportsViewModel) -> some View {
        if !viewModel.categorySpending.isEmpty {
            card(title: "Spending by Category") {
                Chart(viewModel.categorySpending) { item in
                    BarMark(
                        x: .value("Amount", item.amount.doubleValue),
                        y: .value("Category", item.name)
                    )
                    .foregroundStyle(Color(hex: item.colorHex))
                    .annotation(position: .trailing, alignment: .leading) {
                        Text(CurrencyFormatter.string(from: item.amount))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: CGFloat(viewModel.categorySpending.count) * 40 + 20)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Spending by category")
                .accessibilityValue(
                    viewModel.categorySpending
                        .prefix(6)
                        .map { "\($0.name) \(CurrencyFormatter.string(from: $0.amount))" }
                        .joined(separator: ", ")
                )

                Divider()

                // Tap a category to drop down its transactions for the selected range.
                VStack(spacing: 0) {
                    ForEach(viewModel.categorySpending) { item in
                        categoryRow(item, viewModel: viewModel)
                        if item.name != viewModel.categorySpending.last?.name {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func categoryRow(_ item: ReportsViewModel.CategorySpending, viewModel: ReportsViewModel) -> some View {
        let isExpanded = expandedCategory == item.name
        let transactions = viewModel.transactionsByCategory[item.name] ?? []

        Button {
            withAnimation(.spring(duration: 0.3)) {
                expandedCategory = isExpanded ? nil : item.name
            }
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(hex: item.colorHex))
                    .frame(width: 10, height: 10)
                Text(item.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                Text("\(transactions.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.systemGray5), in: Capsule())
                Spacer(minLength: 8)
                Text(CurrencyFormatter.string(from: item.amount))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if isExpanded {
            transactionDropDown(transactions)
        }
    }

    /// The expanded transaction list. Past a handful of rows it scrolls within a fixed height
    /// instead of stretching the card off the screen.
    @ViewBuilder
    private func transactionDropDown(_ transactions: [Transaction]) -> some View {
        let rows = VStack(spacing: 0) {
            ForEach(transactions) { transaction in
                TransactionRowView(transaction: transaction)
                if transaction.persistentModelID != transactions.last?.persistentModelID {
                    Divider().padding(.leading, 44)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)

        Group {
            if transactions.count > 5 {
                ScrollView {
                    rows
                }
                .frame(height: 320)
            } else {
                rows
            }
        }
        .background(Color(.systemGray6).opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Income vs expense

    @ViewBuilder
    private func incomeExpenseCard(_ viewModel: ReportsViewModel) -> some View {
        if viewModel.monthlyFlows.count > 1 {
            let bars = viewModel.monthlyFlows.flatMap { flow in
                [
                    FlowBar(month: flow.month, type: "Income", amount: flow.income),
                    FlowBar(month: flow.month, type: "Expense", amount: flow.expense)
                ]
            }
            card(title: "Income vs. Expenses") {
                Chart(bars) { bar in
                    BarMark(
                        x: .value("Month", bar.month, unit: .month),
                        y: .value("Amount", bar.amount.doubleValue)
                    )
                    .foregroundStyle(by: .value("Type", bar.type))
                    .position(by: .value("Type", bar.type))
                }
                .chartForegroundStyleScale(["Income": Color.green, "Expense": Color.red])
                .frame(height: 220)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Monthly income versus expenses")
                .accessibilityValue(
                    viewModel.monthlyFlows
                        .map { "\(DateFormatting.monthYear($0.month)): income \(CurrencyFormatter.string(from: $0.income)), expenses \(CurrencyFormatter.string(from: $0.expense))" }
                        .joined(separator: ". ")
                )
            }
        }
    }

    // MARK: - Month over month

    @ViewBuilder
    private func monthOverMonthCard(_ viewModel: ReportsViewModel) -> some View {
        if let mom = viewModel.monthOverMonthDelta {
            let delta = mom.current - mom.previous
            let isUp = delta > 0
            card(title: "Month over Month") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Spending change")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text(CurrencyFormatter.string(from: abs(delta)))
                            .font(.title3.bold())
                            .foregroundStyle(isUp ? .red : .green)
                    }
                    Spacer()
                    Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                        .font(.title)
                        .foregroundStyle(isUp ? .red : .green)
                }
            }
        }
    }

    private func netWorthAccessibilitySummary(_ viewModel: ReportsViewModel) -> String {
        guard let first = viewModel.netWorthPoints.first, let last = viewModel.netWorthPoints.last else {
            return "No data"
        }
        return "From \(CurrencyFormatter.string(from: first.value)) to \(CurrencyFormatter.string(from: last.value))"
    }

    // MARK: - Card chrome

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct FlowBar: Identifiable {
    var id: String { "\(month.timeIntervalSince1970)-\(type)" }
    let month: Date
    let type: String
    let amount: Decimal
}

private extension Decimal {
    var doubleValue: Double { (self as NSDecimalNumber).doubleValue }
}

#Preview {
    NavigationStack { ReportsView() }
        .modelContainer(for: LedgerSchema.models, inMemory: true)
}
