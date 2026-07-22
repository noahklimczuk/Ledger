import SwiftUI
import SwiftData

/// Detail for one recurring series: what it is, how confident Ledger is, its amount history (with a
/// small sparkline), the predicted next charge, and the lifecycle actions. Reached from the recurring
/// list and its insights.
struct RecurringDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let series: RecurringSeries
    var viewModel: RecurringViewModel?

    /// Past transactions that make up this series, newest first — loaded by matching the normalized
    /// merchant key so the detail can show real history and a sparkline.
    @State private var history: [Transaction] = []

    var body: some View {
        List {
            headerSection
            if let change = series.priceChange { priceChangeSection(change) }
            statsSection
            if !history.isEmpty { historySection }
            actionsSection
        }
        .navigationTitle(series.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .accent(.recurring)
        .accentWash(.recurring)
        .scrollContentBackground(.hidden)
        .task { loadHistory() }
    }

    // MARK: - Header

    private var headerSection: some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: series.isIncome ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(series.isIncome ? Palette.income : Palette.amber)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(CurrencyFormatter.string(from: series.averageAmount))
                        .font(.title2.bold())
                        .foregroundStyle(series.isIncome ? Palette.income : Color.primary)
                    Text("\(series.cadence.displayName) · \(series.status.displayName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 4)
            confidenceRow
        }
    }

    private var confidenceRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Detection confidence").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int((series.detectionConfidence * 100).rounded()))%")
                    .font(.caption.weight(.semibold))
            }
            ProgressView(value: min(max(series.detectionConfidence, 0), 1))
                .tint(confidenceColor)
        }
        .padding(.vertical, 2)
    }

    private var confidenceColor: Color {
        switch series.detectionConfidence {
        case ..<0.5: Palette.expense
        case ..<0.72: Palette.amber
        default: Palette.income
        }
    }

    // MARK: - Price change

    private func priceChangeSection(_ change: RecurringSeries.PriceChange) -> some View {
        Section("Price Change") {
            HStack(spacing: 12) {
                Image(systemName: change.isIncrease ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(change.isIncrease ? Palette.expense : Palette.income)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(CurrencyFormatter.string(from: change.previous)) → \(CurrencyFormatter.string(from: change.current))")
                        .fontWeight(.medium)
                    Text("\(change.isIncrease ? "Up" : "Down") \(Int((abs(change.fraction) * 100).rounded()))% from its usual amount")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Stats

    private var statsSection: some View {
        Section("Details") {
            if series.status == .ended {
                statRow("Last charge", value: DateFormatting.medium(series.lastOccurrence))
            } else {
                // Roll a stale next-expected forward so this never reads as a date in the past.
                statRow("Predicted next", value: "\(CurrencyFormatter.string(from: series.predictedAmount)) · \(DateFormatting.medium(series.projectedNextDate()))")
            }
            statRow("Monthly equivalent", value: CurrencyFormatter.string(from: series.monthlyEquivalent))
            statRow("Yearly", value: CurrencyFormatter.string(from: series.annualEquivalent))
            statRow("Times seen", value: "\(series.occurrenceCount)")
            if let first = series.firstOccurrence {
                statRow("Tracking since", value: DateFormatting.medium(first))
            }
            // Only surfaced for a cancelled series to explain why — an active one shows a
            // rolled-forward "Predicted next", so an "Overdue" row next to it would contradict it.
            if series.status == .ended {
                let overdue = series.daysOverdue()
                if overdue > 0 {
                    statRow("Overdue", value: "\(overdue) days")
                }
            }
        }
    }

    private func statRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium).multilineTextAlignment(.trailing)
        }
    }

    // MARK: - History

    private var historySection: some View {
        Section("History") {
            Sparkline(amounts: history.reversed().map { abs(($0.amount as NSDecimalNumber).doubleValue) })
                .frame(height: 44)
                .padding(.vertical, 6)
            ForEach(history.prefix(12)) { transaction in
                HStack {
                    Text(DateFormatting.medium(transaction.date))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(CurrencyFormatter.string(from: transaction.amount, currencyCode: transaction.account?.currencyCode ?? "CAD"))
                        .fontWeight(.medium)
                }
                .font(.subheadline)
            }
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionsSection: some View {
        Section {
            switch series.status {
            case .suggested:
                actionButton("Confirm as Recurring", systemImage: "checkmark.circle.fill", tint: Palette.income) { viewModel?.confirm(series) }
                actionButton("Not Recurring", systemImage: "xmark.circle", tint: Palette.expense) { viewModel?.ignore(series) }
            case .active:
                actionButton("Pause", systemImage: "pause.circle", tint: Palette.amber) { viewModel?.pause(series) }
                actionButton("Mark as Ended", systemImage: "xmark.circle", tint: .secondary) { viewModel?.markEnded(series) }
                actionButton("Ignore", systemImage: "bell.slash", tint: Palette.expense) { viewModel?.ignore(series) }
            case .paused:
                actionButton("Resume", systemImage: "play.circle", tint: Palette.income) { viewModel?.resume(series) }
                actionButton("Ignore", systemImage: "bell.slash", tint: Palette.expense) { viewModel?.ignore(series) }
            case .ended:
                actionButton("Reactivate", systemImage: "arrow.clockwise", tint: Palette.income) { viewModel?.reactivate(series) }
                actionButton("Ignore", systemImage: "bell.slash", tint: Palette.expense) { viewModel?.ignore(series) }
            case .ignored:
                actionButton("Restore", systemImage: "bell", tint: Palette.peri) { viewModel?.restore(series) }
            }
        }
    }

    private func actionButton(_ title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            action()
            dismiss()
        } label: {
            Label(title, systemImage: systemImage).frame(maxWidth: .infinity)
        }
        .tint(tint)
    }

    private func loadHistory() {
        let all = (try? modelContext.fetch(FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        // Mirror detection's own filters (archived-account and transfer exclusion) so the history and
        // sparkline reflect exactly the transactions the series was built from.
        history = all.filter {
            RecurringDetectionService.normalizeMerchant($0.merchant) == series.merchantKey
                && $0.countsTowardTotals
                && !$0.isTransfer
        }
    }
}

/// A minimal inline bar sparkline for a series' amount history (oldest → newest).
private struct Sparkline: View {
    let amounts: [Double]

    var body: some View {
        GeometryReader { proxy in
            let maxValue = amounts.max() ?? 1
            let count = max(amounts.count, 1)
            let spacing: CGFloat = 3
            let barWidth = max((proxy.size.width - spacing * CGFloat(count - 1)) / CGFloat(count), 1)
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(amounts.enumerated()), id: \.offset) { _, value in
                    let ratio = maxValue > 0 ? value / maxValue : 0
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor.opacity(0.6))
                        .frame(width: barWidth, height: max(proxy.size.height * ratio, 2))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}
