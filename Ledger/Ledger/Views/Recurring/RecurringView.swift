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
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MONTHLY RECURRING")
                            .font(.appCaption.weight(.heavy))
                            .tracking(1.1)
                            .foregroundStyle(.white.opacity(0.85))
                        CountingCurrency(value: viewModel.monthlyRecurringExpense)
                            .font(.appDisplay)
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        Text("≈ \(CurrencyFormatter.string(from: viewModel.annualRecurringExpense)) / year")
                            .font(.appCaption)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Spacer()
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                Divider().overlay(Color.white.opacity(0.25))
                HStack {
                    summaryStat("Subscriptions", "\(viewModel.activeSubscriptionCount)")
                    Spacer()
                    if viewModel.monthlyRecurringIncome > 0 {
                        summaryStat("Income / mo", CurrencyFormatter.string(from: viewModel.monthlyRecurringIncome))
                        Spacer()
                    }
                    summaryStat("Next 30 days", CurrencyFormatter.string(from: viewModel.next30DaysOutflow))
                }
            }
            .padding(6)
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            .listRowBackground(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Accent.recurring.gradient)
                    .padding(4)
            )
        }
    }

    private func summaryStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.appHeadline.weight(.heavy))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    // MARK: - Insights

    private func insightsSection(_ viewModel: RecurringViewModel) -> some View {
        Section("Needs Attention") {
            ForEach(viewModel.insights) { insight in
                insightRow(insight)
            }
        }
    }

    @ViewBuilder
    private func insightRow(_ insight: RecurringViewModel.Insight) -> some View {
        let content = HStack(spacing: 12) {
            Image(systemName: insight.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(insight.tint, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(insight.title).font(.subheadline.weight(.semibold))
                Text(insight.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
        }
        // A navigable insight is wrapped in a NavigationLink, which supplies its own disclosure
        // chevron — so we don't add one here (doing both showed a double arrow).
        if let series = insight.series {
            NavigationLink(value: series) { content }
        } else {
            content
        }
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
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundStyle(prominent ? Color.white : Color.primary)
                .background(prominent ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
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
                        Text(charge.series.displayName).fontWeight(.medium)
                        Text(DateFormatting.relativeUpcoming(charge.date))
                            .font(.caption).foregroundStyle(.secondary)
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
            Image(systemName: series.isIncome ? "arrow.down.left" : "arrow.up.right")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(
                    LinearGradient(
                        colors: series.isIncome ? [Palette.emerald, Palette.emeraldDeep] : [Palette.pink, Palette.pinkDeep],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(series.displayName).fontWeight(.medium)
                Text(scheduleLine)
                    .font(.caption).foregroundStyle(.secondary)
                badges
            }
            Spacer(minLength: 6)
            Text(CurrencyFormatter.string(from: series.averageAmount))
                .fontWeight(.semibold)
                .foregroundStyle(series.isIncome ? Palette.income : Color.primary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
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
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
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
