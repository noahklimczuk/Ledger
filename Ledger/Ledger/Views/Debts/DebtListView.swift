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
                                .buttonStyle(.pressable)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                                        viewModel.delete(debt)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            } else {
                LoadingView()
            }
        }
        .navigationTitle("Debt")
        .accentWash(.debt)
        .accent(.debt)
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
                    Text("TOTAL OWED").font(.appCaption.weight(.heavy)).tracking(1).foregroundStyle(.secondary)
                    Text(CurrencyFormatter.string(from: viewModel.totalOwed))
                        .font(.appNumber)
                        .foregroundStyle(Palette.expense)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Monthly").font(.appCaption).foregroundStyle(.secondary)
                    Text(CurrencyFormatter.string(from: viewModel.totalMonthlyPayment))
                        .font(.appTitle3.weight(.bold))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
            }
            .card()
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }
}

private struct DebtRow: View {
    let debt: Debt

    private var projection: DebtPayoffCalculator.Projection? {
        DebtPayoffCalculator.project(balance: debt.currentBalance, annualInterestRate: debt.annualInterestRate, monthlyPayment: debt.minimumPayment)
    }

    var body: some View {
        HStack(spacing: 14) {
            IconBadge(systemName: debt.kind.sfSymbolName, accent: .debt, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(debt.name).font(.appBodyMedium)
                Text(subtitle)
                    .font(.appCaption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(CurrencyFormatter.string(from: debt.currentBalance))
                .font(.appBody.weight(.heavy))
                .foregroundStyle(Palette.expense)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .card()
        .contentShape(Rectangle())
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
