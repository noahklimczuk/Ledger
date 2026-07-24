import SwiftUI
import SwiftData

struct RecurringView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: RecurringViewModel?
    @State private var isPresentingNewTransaction = false

    var body: some View {
        Group {
            if let viewModel {
                if !viewModel.hasAnySeries {
                    EmptyStateView(
                        emoji: "🔄",
                        systemImage: "arrow.triangle.2.circlepath",
                        title: "No Subscriptions Yet",
                        message: "Add a few transactions or import a statement and Ledger will detect your repeating bills and income.",
                        actionTitle: "Add Transaction",
                        action: { isPresentingNewTransaction = true }
                    )
                } else {
                    List {
                        summarySection(viewModel)
                        if !viewModel.insights.isEmpty { insightsSection(viewModel) }
                        if !viewModel.suggestedSeries.isEmpty { suggestedSection(viewModel) }
                        if !viewModel.upcoming.isEmpty { upcomingSection(viewModel) }
                        if !viewModel.activeExpenses.isEmpty {
                            seriesSection(viewModel, title: "Subscriptions & Bills", series: viewModel.activeExpenses)
                        }
                        if !viewModel.incomeSeries.isEmpty {
                            seriesSection(viewModel, title: "Recurring Income", series: viewModel.incomeSeries)
                        }
                        if !viewModel.pausedSeries.isEmpty {
                            seriesSection(viewModel, title: "Paused", series: viewModel.pausedSeries)
                        }
                        if !viewModel.endedSeries.isEmpty {
                            seriesSection(viewModel, title: "Ended", series: viewModel.endedSeries)
                        }
                        if !viewModel.ignoredSeries.isEmpty {
                            seriesSection(viewModel, title: "Ignored", series: viewModel.ignoredSeries)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            } else {
                LoadingView()
            }
        }
        .navigationTitle("Subscriptions")
        .accentWash(.recurring)
        .accent(.recurring)
        .navigationDestination(for: RecurringSeries.self) { series in
            RecurringDetailView(series: series, viewModel: viewModel)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 16) {
                    Button {
                        isPresentingNewTransaction = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add Transaction")

                    Button {
                        viewModel?.load()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Rescan")
                }
            }
        }
        .sheet(isPresented: $isPresentingNewTransaction, onDismiss: { viewModel?.load() }) {
            TransactionEditView(transaction: nil)
        }
        .task {
            if viewModel == nil { viewModel = RecurringViewModel(modelContext: modelContext) }
            viewModel?.load()
        }
    }

    // MARK: - Summary

    private func summarySection(_ viewModel: RecurringViewModel) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    summaryColumn(
                        label: "Bills & subs",
                        value: viewModel.monthlyRecurringExpense,
                        suffix: "/mo",
                        color: Color.primary
                    )
                    Spacer(minLength: 16)
                    summaryColumn(
                        label: "Income",
                        value: viewModel.monthlyRecurringIncome,
                        suffix: nil,
                        color: Palette.income,
                        alignment: .trailing
                    )
                }

                RecurringSummaryBar(
                    expense: viewModel.monthlyRecurringExpense,
                    income: viewModel.monthlyRecurringIncome
                )
            }
            .padding(Theme.cardPadding)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        .listRowBackground(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Color.appSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .strokeBorder(Color.appHairline, lineWidth: 1)
                )
                .padding(4)
        )
    }

    private func summaryColumn(
        label: String,
        value: Decimal,
        suffix: String?,
        color: Color,
        alignment: HorizontalAlignment = .leading
    ) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(label.uppercased())
                .font(.appCaption2.weight(.heavy))
                .tracking(0.3)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(CurrencyFormatter.string(from: value))
                    .font(.appTitle.weight(.heavy))
                    .foregroundStyle(color)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if let suffix {
                    Text(suffix)
                        .font(.appCaption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Insights

    private func insightsSection(_ viewModel: RecurringViewModel) -> some View {
        Section {
            ForEach(viewModel.insights) { insight in
                insightRow(insight)
            }
        }
    }

    private func insightRow(_ insight: RecurringViewModel.Insight) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let series = insight.series {
                NavigationLink(value: series) { insightCard(insight) }
            } else {
                insightCard(insight)
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
    }

    private func insightCard(_ insight: RecurringViewModel.Insight) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Palette.peri, Palette.greenDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 20, height: 20)

                Text("Heads up")
                    .font(.appCaption2.weight(.black))
                    .foregroundStyle(Palette.peri)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(insight.title)
                    .font(.appSubheadline.weight(.heavy))
                    .foregroundStyle(Color.primary)

                Text(insight.detail)
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Palette.peri.opacity(0.10), Palette.peri.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Palette.peri.opacity(0.18), lineWidth: 1)
        )
    }

    // MARK: - Suggested (review)

    private func suggestedSection(_ viewModel: RecurringViewModel) -> some View {
        Section {
            ForEach(viewModel.suggestedSeries) { series in
                VStack(spacing: 10) {
                    NavigationLink(value: series) {
                        RecurringRow(series: series)
                    }
                    // These live in the same List row as the NavigationLink above, so they must be
                    // borderless: a bordered button here has its tap swallowed by the row's
                    // navigation instead of confirming/dismissing. The filled look is drawn on the
                    // label so the buttons still read as primary/secondary actions.
                    HStack(spacing: 10) {
                        reviewButton("Confirm", systemImage: "checkmark", prominent: true) {
                            viewModel.confirm(series)
                        }
                        reviewButton("Not recurring", systemImage: "xmark", prominent: false) {
                            viewModel.ignore(series)
                        }
                    }
                }
            }
        } header: {
            Text("Review")
        }
    }

    private func reviewButton(_ title: String, systemImage: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.appSubheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundStyle(prominent ? Color.appBackground : Color.primary)
                .background(prominent ? Color.accentColor : Color.appSurface, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.borderless)
    }

    // MARK: - Upcoming

    private func upcomingSection(_ viewModel: RecurringViewModel) -> some View {
        Section {
            ForEach(viewModel.upcoming.prefix(8)) { charge in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(charge.series.displayName).font(.appSubheadline.weight(.medium))
                        Text(DateFormatting.relativeUpcoming(charge.date))
                            .font(.appCaption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(CurrencyFormatter.string(from: charge.amount))
                        .foregroundStyle(charge.amount > 0 ? Palette.income : Color.primary)
                }
            }
        } header: {
            Text("Upcoming (next 60 days)")
        }
    }

    // MARK: - Series sections

    private func seriesSection(_ viewModel: RecurringViewModel, title: String, series: [RecurringSeries]) -> some View {
        Section(title) {
            ForEach(series) { item in
                NavigationLink(value: item) {
                    RecurringRow(series: item)
                }
                .swipeActions(edge: .trailing) {
                    swipeActions(viewModel, series: item)
                }
                .contextMenu {
                    menuActions(viewModel, series: item)
                }
            }
        }
    }

    @ViewBuilder
    private func swipeActions(_ viewModel: RecurringViewModel, series: RecurringSeries) -> some View {
        switch series.status {
        case .active:
            Button { viewModel.pause(series) } label: { Label("Pause", systemImage: "pause.circle") }
                .tint(Palette.amber)
            Button(role: .destructive) { viewModel.ignore(series) } label: { Label("Ignore", systemImage: "bell.slash") }
        case .paused:
            Button { viewModel.resume(series) } label: { Label("Resume", systemImage: "play.circle") }
                .tint(Palette.income)
        case .ended:
            Button { viewModel.reactivate(series) } label: { Label("Reactivate", systemImage: "arrow.clockwise") }
                .tint(Palette.income)
            Button(role: .destructive) { viewModel.ignore(series) } label: { Label("Ignore", systemImage: "bell.slash") }
        case .ignored:
            Button { viewModel.restore(series) } label: { Label("Restore", systemImage: "bell") }
                .tint(Palette.peri)
        case .suggested:
            Button { viewModel.confirm(series) } label: { Label("Confirm", systemImage: "checkmark") }
                .tint(Palette.income)
        }
    }

    @ViewBuilder
    private func menuActions(_ viewModel: RecurringViewModel, series: RecurringSeries) -> some View {
        if series.status == .active {
            Button { viewModel.pause(series) } label: { Label("Pause", systemImage: "pause.circle") }
            Button { viewModel.markEnded(series) } label: { Label("Mark Ended", systemImage: "xmark.circle") }
        }
        if series.status == .paused {
            Button { viewModel.resume(series) } label: { Label("Resume", systemImage: "play.circle") }
        }
        if series.status == .ended {
            Button { viewModel.reactivate(series) } label: { Label("Reactivate", systemImage: "arrow.clockwise") }
        }
        if series.status == .ignored {
            Button { viewModel.restore(series) } label: { Label("Restore", systemImage: "bell") }
        } else {
            Button(role: .destructive) { viewModel.ignore(series) } label: { Label("Ignore", systemImage: "bell.slash") }
        }
    }
}

/// One recurring series row: icon, name, cadence + next date, amount, and small badges for a price
/// change or a low-confidence detection.
private struct RecurringRow: View {
    let series: RecurringSeries

    var body: some View {
        HStack(spacing: 12) {
            BloomRowIcon(emoji: series.displayIcon, size: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(series.displayName)
                    .font(.appSubheadline.weight(.heavy))
                    .foregroundStyle(Color.primary)
                Text(scheduleLine)
                    .font(.appCaption).foregroundStyle(.secondary)
                badges
            }
            Spacer(minLength: 6)
            Text(CurrencyFormatter.string(from: series.averageAmount))
                .font(.appSubheadline.weight(.heavy))
                .foregroundStyle(series.isIncome ? Palette.income : Palette.expense)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    /// Cadence plus the next (or, for a cancelled series, the last) charge date. `nextExpected` can
    /// have slipped into the past, so an active/paused/suggested series shows a rolled-forward date
    /// and an ended one shows when it last charged rather than a meaningless future "next".
    private var scheduleLine: String {
        if series.status == .ended {
            return "\(series.cadence.displayName) · last \(DateFormatting.medium(series.lastOccurrence))"
        }
        return "\(series.cadence.displayName) · next \(DateFormatting.medium(series.projectedNextDate()))"
    }

    @ViewBuilder
    private var badges: some View {
        HStack(spacing: 6) {
            if let change = series.priceChange {
                chip(
                    text: "\(change.isIncrease ? "↑" : "↓") \(CurrencyFormatter.string(from: change.current))",
                    color: change.isIncrease ? Palette.expense : Palette.income
                )
            }
            if series.status == .suggested {
                chip(text: "\(Int((series.detectionConfidence * 100).rounded()))% match", color: Palette.peri)
            }
            if series.status == .ended {
                chip(text: "Likely cancelled", color: .secondary)
            }
        }
    }

    private func chip(text: String, color: Color) -> some View {
        Text(text)
            .font(.appCaption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

// MARK: - Summary bar

private struct RecurringSummaryBar: View {
    let expense: Decimal
    let income: Decimal

    var body: some View {
        GeometryReader { geo in
            let total = NSDecimalNumber(decimal: max(expense + income, 0)).doubleValue
            let expenseFraction = total > 0 ? NSDecimalNumber(decimal: max(expense, 0)).doubleValue / total : 0
            let incomeFraction = total > 0 ? 1.0 - expenseFraction : 0
            let numberOfBars = (expenseFraction > 0 ? 1 : 0) + (incomeFraction > 0 ? 1 : 0)
            let availableWidth = max(0, geo.size.width - CGFloat(numberOfBars - 1) * 2)

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.appSurface)
                    .shadow(color: Color.bloomShadow, radius: 4, x: 2, y: 2)
                    .shadow(color: Color.bloomHighlight, radius: 3, x: -1, y: -1)

                HStack(spacing: 2) {
                    if expenseFraction > 0 {
                        RoundedRectangle(cornerRadius: 999, style: .continuous)
                            .fill(LinearGradient(colors: [Palette.green, Palette.greenDeep], startPoint: .leading, endPoint: .trailing))
                            .frame(width: availableWidth * CGFloat(expenseFraction), height: 12)
                    }

                    if incomeFraction > 0 {
                        RoundedRectangle(cornerRadius: 999, style: .continuous)
                            .fill(LinearGradient(colors: [Palette.amber, Palette.peach], startPoint: .leading, endPoint: .trailing))
                            .frame(width: availableWidth * CGFloat(incomeFraction), height: 12)
                    }
                }
            }
        }
        .frame(height: 12)
    }
}

extension RecurringViewModel.Insight {
    var symbol: String {
        switch kind {
        case .needsReview: "questionmark.circle.fill"
        case .likelyCancelled: "xmark.circle.fill"
        case .priceIncrease: "arrow.up.right.circle.fill"
        case .priceDecrease: "arrow.down.right.circle.fill"
        case .dueThisWeek: "calendar.badge.clock"
        }
    }

    var tint: Color {
        switch kind {
        case .needsReview: Palette.peri
        case .likelyCancelled: .gray
        case .priceIncrease: Palette.expense
        case .priceDecrease: Palette.income
        case .dueThisWeek: Palette.amber
        }
    }
}

#Preview {
    NavigationStack { RecurringView() }
        .modelContainer(for: LedgerSchema.models, inMemory: true)
}
