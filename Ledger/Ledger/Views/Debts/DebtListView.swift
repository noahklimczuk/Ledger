import SwiftUI
import SwiftData

struct DebtListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: DebtsViewModel?
    @State private var isPresentingNew = false
    @State private var editingDebt: Debt?

    var body: some View {
        Group {
            if let viewModel {
                if viewModel.debts.isEmpty {
                    EmptyStateView(
                        systemImage: "creditcard.trianglebadge.exclamationmark",
                        title: "No Debts Tracked",
                        message: "Add a credit card, loan, or line of credit to track what you owe and estimate a payoff timeline.",
                        actionTitle: "Add Debt"
                    ) {
                        isPresentingNew = true
                    }
                } else {
                    List {
                        summarySection(viewModel)
                        Section("Debts") {
                            ForEach(viewModel.debts) { debt in
                                Button { editingDebt = debt } label: {
                                    DebtRow(debt: debt)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        viewModel.delete(debt)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                LoadingView()
            }
        }
        .navigationTitle("Debt")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isPresentingNew = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Debt")
            }
        }
        .sheet(isPresented: $isPresentingNew, onDismiss: { viewModel?.load() }) {
            DebtEditView(debt: nil, viewModel: viewModel)
        }
        .sheet(item: $editingDebt, onDismiss: { viewModel?.load() }) { debt in
            DebtEditView(debt: debt, viewModel: viewModel)
        }
        .task {
            if viewModel == nil { viewModel = DebtsViewModel(modelContext: modelContext) }
            viewModel?.load()
        }
    }

    private func summarySection(_ viewModel: DebtsViewModel) -> some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total Owed").font(.caption).foregroundStyle(.secondary)
                    Text(CurrencyFormatter.string(from: viewModel.totalOwed))
                        .font(.title2).fontWeight(.semibold)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Monthly Payments").font(.caption).foregroundStyle(.secondary)
                    Text(CurrencyFormatter.string(from: viewModel.totalMonthlyPayment))
                        .font(.title3).fontWeight(.medium)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct DebtRow: View {
    let debt: Debt

    private var projection: DebtPayoffCalculator.Projection? {
        DebtPayoffCalculator.project(balance: debt.currentBalance, annualInterestRate: debt.annualInterestRate, monthlyPayment: debt.minimumPayment)
    }

    var body: some View {
        HStack {
            Image(systemName: debt.kind.sfSymbolName)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(.red, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(debt.name).fontWeight(.medium)
                Text(subtitle)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(CurrencyFormatter.string(from: debt.currentBalance))
                .fontWeight(.medium)
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        var parts: [String] = [debt.kind.displayName]
        if debt.annualInterestRate > 0 {
            parts.append(String(format: "%.2f%% APR", debt.annualInterestRate))
        }
        if let projection {
            parts.append(projection.months == 0 ? "Paid off" : "~\(DebtPayoffCalculator.durationText(months: projection.months)) left")
        } else if debt.minimumPayment > 0 {
            parts.append("payment too low")
        }
        return parts.joined(separator: " · ")
    }
}

#Preview {
    NavigationStack { DebtListView() }
        .modelContainer(for: LedgerSchema.models, inMemory: true)
}
