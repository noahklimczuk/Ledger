import Charts
import SwiftUI
import SwiftData

struct ReportsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: ReportsViewModel?
    /// The category whose transactions are being drilled into from the spending doughnut.
    @State private var drilldownCategory: Category?

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
        .accentWash(.reports)
        .accent(.reports)
        .navigationDestination(item: $drilldownCategory) { category in
            if let viewModel {
                CategoryTransactionsView(
                    category: category,
                    interval: viewModel.currentInterval,
                    subtitle: viewModel.rangeLabel
                )
            }
        }
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
        HStack(spacing: 10) {
            summaryTile("Income", value: viewModel.totalIncome, color: Palette.income)
            summaryTile("Expenses", value: viewModel.totalExpense, color: Palette.expense)
            summaryTile("Net", value: viewModel.net, color: viewModel.net < 0 ? Palette.expense : Palette.indigo)
        }
    }

    private func summaryTile(_ label: String, value: Decimal, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(CurrencyFormatter.string(from: value))
                .font(.appTitle3.weight(.heavy))
                .foregroundStyle(color)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(label).font(.appCaption.weight(.semibold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
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
                InteractiveDonutChart(
                    segments: viewModel.categorySpending.map { item in
                        DonutSegment(
                            id: item.id,
                            label: item.name,
                            value: item.amount,
                            color: Color(hex: item.colorHex),
                            isSelectable: item.category != nil
                        )
                    },
                    centerCaption: "Spent",
                    onSelect: { segment in
                        if let item = viewModel.categorySpending.first(where: { $0.id == segment.id }) {
                            drilldownCategory = item.category
                        }
                    }
                )
                Text("Tap a slice or row to see its transactions.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
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
            SectionHeadline(title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
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
