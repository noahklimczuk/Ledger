import SwiftUI
import SwiftData

/// Wrapper so this screen's category drill-down uses a *distinct* navigation type from the
/// dashboard it's pushed from — two `navigationDestination(item:)` for the same `Category` type in
/// one stack can collapse to the root one and break the deeper drill-down.
private struct SafeToSpendDrilldown: Hashable {
    let category: Category
}

/// Pushed from the dashboard's Safe-to-Spend card. Explains the number two ways: a composition
/// ring showing how this month's income splits into budgeted / reserved-for-bills / safe-to-spend,
/// and a spending-by-category doughnut whose slices drill into their transactions.
struct SafeToSpendDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: DashboardViewModel?
    @State private var drilldown: SafeToSpendDrilldown?

    var body: some View {
        Group {
            if let viewModel {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headline(viewModel)
                        compositionCard(viewModel)
                        categoryCard(viewModel)
                    }
                    .padding()
                }
            } else {
                LoadingView()
            }
        }
        .navigationTitle("Safe to Spend")
        .navigationBarTitleDisplayMode(.inline)
        .accent(.dashboard)
        .accentWash(.dashboard)
        .navigationDestination(item: $drilldown) { drilldown in
            CategoryTransactionsView(category: drilldown.category, month: .now)
        }
        .task {
            if viewModel == nil { viewModel = DashboardViewModel(modelContext: modelContext) }
            viewModel?.load()
        }
    }

    private func headline(_ viewModel: DashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Safe to spend this month")
                .font(.appSubheadline)
                .foregroundStyle(.secondary)
            Text(CurrencyFormatter.string(from: viewModel.safeToSpend))
                .font(.appMoney)
                .foregroundStyle(viewModel.safeToSpend < 0 ? Palette.expense : Color.primary)
            Text("What's left of your income after money you've budgeted to categories and reserved for upcoming bills.")
                .font(.appFootnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func compositionCard(_ viewModel: DashboardViewModel) -> some View {
        let segments = compositionSegments(viewModel)
        if !segments.isEmpty {
            card(title: "Where your income goes") {
                InteractiveDonutChart(
                    segments: segments,
                    centerCaption: "safe to spend",
                    centerValueText: CurrencyFormatter.string(from: viewModel.safeToSpend)
                )
                if viewModel.safeToSpend < 0 {
                    Text("Your budgets and reserved bills add up to more than your income this month.")
                        .font(.appCaption2)
                        .foregroundStyle(Palette.amber)
                }
            }
        }
    }

    @ViewBuilder
    private func categoryCard(_ viewModel: DashboardViewModel) -> some View {
        let segments = categorySegments(viewModel)
        if !segments.isEmpty {
            card(title: "This month's spending") {
                InteractiveDonutChart(
                    segments: segments,
                    centerCaption: "Spent",
                    onSelect: { segment in
                        if let slice = viewModel.topCategories.first(where: { $0.id == segment.id }),
                           let category = slice.category {
                            drilldown = SafeToSpendDrilldown(category: category)
                        }
                    }
                )
            }
        }
    }

    // MARK: - Segments

    private func compositionSegments(_ viewModel: DashboardViewModel) -> [DonutSegment] {
        var segments: [DonutSegment] = []
        if viewModel.monthBudgetTotal > 0 {
            segments.append(DonutSegment(id: "budgeted", label: "Budgeted to categories", value: viewModel.monthBudgetTotal, color: .accentColor, isSelectable: false))
        }
        if viewModel.reservedForBills > 0 {
            segments.append(DonutSegment(id: "reserved", label: "Reserved for bills", value: viewModel.reservedForBills, color: Palette.amber, isSelectable: false))
        }
        if viewModel.safeToSpend > 0 {
            segments.append(DonutSegment(id: "safe", label: "Safe to spend", value: viewModel.safeToSpend, color: Palette.income, isSelectable: false))
        }
        return segments
    }

    private func categorySegments(_ viewModel: DashboardViewModel) -> [DonutSegment] {
        var segments = viewModel.topCategories.map { slice in
            DonutSegment(
                id: slice.id,
                label: slice.name,
                value: slice.amount,
                color: Color(hex: slice.colorHex),
                isSelectable: slice.category != nil
            )
        }
        let shown = viewModel.topCategories.reduce(Decimal(0)) { $0 + $1.amount }
        let other = viewModel.monthSpending - shown
        if other > 0 {
            segments.append(DonutSegment(id: "other", label: "Other", value: other, color: Color(.systemGray3), isSelectable: false))
        }
        return segments
    }

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.appHeadline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.appHairline, lineWidth: 1)
        )
    }
}
