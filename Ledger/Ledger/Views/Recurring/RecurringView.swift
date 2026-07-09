import SwiftUI
import SwiftData

struct RecurringView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: RecurringViewModel?

    var body: some View {
        Group {
            if let viewModel {
                if viewModel.activeSeries.isEmpty && viewModel.ignoredSeries.isEmpty {
                    EmptyStateView(
                        systemImage: "arrow.triangle.2.circlepath",
                        title: "No Recurring Charges Found",
                        message: "Once you have a few months of transactions, Ledger spots subscriptions and regular bills automatically."
                    )
                } else {
                    List {
                        forecastSection(viewModel)
                        if !viewModel.incomeSeries.isEmpty {
                            seriesSection(viewModel, title: "Income", series: viewModel.incomeSeries)
                        }
                        if !viewModel.expenseSeries.isEmpty {
                            seriesSection(viewModel, title: "Bills & Subscriptions", series: viewModel.expenseSeries)
                        }
                        if !viewModel.ignoredSeries.isEmpty {
                            ignoredSection(viewModel)
                        }
                    }
                }
            } else {
                LoadingView()
            }
        }
        .navigationTitle("Recurring")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel?.load()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task {
            if viewModel == nil { viewModel = RecurringViewModel(modelContext: modelContext) }
            viewModel?.load()
        }
    }

    @ViewBuilder
    private func forecastSection(_ viewModel: RecurringViewModel) -> some View {
        if !viewModel.upcoming.isEmpty {
            Section {
                ForEach(viewModel.upcoming) { charge in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(charge.series.displayName).fontWeight(.medium)
                            Text(DateFormatting.relativeDay(charge.date))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(CurrencyFormatter.string(from: charge.series.averageAmount))
                            .foregroundStyle(charge.series.isIncome ? Color.green : Color.primary)
                    }
                }
            } header: {
                Text("Upcoming (next 60 days)")
            } footer: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Projected outflow (next 30 days): \(CurrencyFormatter.string(from: viewModel.next30DaysOutflow))")
                    if viewModel.next30DaysIncome > 0 {
                        Text("Projected income (next 30 days): \(CurrencyFormatter.string(from: viewModel.next30DaysIncome))")
                    }
                }
            }
        }
    }

    private func seriesSection(_ viewModel: RecurringViewModel, title: String, series: [RecurringSeries]) -> some View {
        Section(title) {
            ForEach(series) { item in
                RecurringRow(series: item)
                    .swipeActions {
                        Button {
                            viewModel.setIgnored(item, ignored: true)
                        } label: {
                            Label("Ignore", systemImage: "bell.slash")
                        }
                        .tint(.gray)
                    }
            }
        }
    }

    private func ignoredSection(_ viewModel: RecurringViewModel) -> some View {
        Section("Ignored") {
            ForEach(viewModel.ignoredSeries) { series in
                RecurringRow(series: series)
                    .foregroundStyle(.secondary)
                    .swipeActions {
                        Button {
                            viewModel.setIgnored(series, ignored: false)
                        } label: {
                            Label("Restore", systemImage: "bell")
                        }
                        .tint(.blue)
                    }
            }
        }
    }
}

private struct RecurringRow: View {
    let series: RecurringSeries

    var body: some View {
        HStack {
            Image(systemName: series.isIncome ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .foregroundStyle(series.isIncome ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(series.displayName).fontWeight(.medium)
                Text("\(series.cadence.displayName) · next \(DateFormatting.medium(series.nextExpected))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(CurrencyFormatter.string(from: series.averageAmount))
                .foregroundStyle(series.isIncome ? Color.green : Color.primary)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack { RecurringView() }
        .modelContainer(for: LedgerSchema.models, inMemory: true)
}
