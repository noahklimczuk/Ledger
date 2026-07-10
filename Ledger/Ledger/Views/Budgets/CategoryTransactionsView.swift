import SwiftUI
import SwiftData

/// All transactions in one category for a given month — reached by tapping a budget row. Shows the
/// month's total for the category up top, then each transaction (tap through to its detail).
struct CategoryTransactionsView: View {
    @Environment(\.modelContext) private var modelContext

    let category: Category
    let month: Date

    @State private var transactions: [Transaction] = []

    private var spent: Decimal {
        transactions.filter { $0.amount < 0 }.reduce(Decimal(0)) { $0 + (-$1.amount) }
    }

    private var income: Decimal {
        transactions.filter { $0.amount > 0 }.reduce(Decimal(0)) { $0 + $1.amount }
    }

    var body: some View {
        Group {
            if transactions.isEmpty {
                EmptyStateView(
                    systemImage: category.sfSymbolName,
                    title: "No Transactions",
                    message: "Nothing in \(category.name) for \(DateFormatting.monthYear(month))."
                )
            } else {
                List {
                    Section {
                        summaryRow
                    }
                    Section("\(transactions.count) transaction\(transactions.count == 1 ? "" : "s")") {
                        ForEach(transactions) { transaction in
                            NavigationLink {
                                TransactionDetailView(transaction: transaction)
                            } label: {
                                TransactionRowView(transaction: transaction)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: category.persistentModelID) { load() }
        // Pushed screen: swiping should go back, not drag to the next tab.
        .disablesTabSwipe()
    }

    private var summaryRow: some View {
        HStack {
            Image(systemName: category.sfSymbolName)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color(hex: category.colorHex), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(DateFormatting.monthYear(month))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(CurrencyFormatter.string(from: spent))
                    .font(.title2.bold())
            }
            Spacer()
            if income > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Income").font(.caption).foregroundStyle(.secondary)
                    Text(CurrencyFormatter.string(from: income))
                        .fontWeight(.medium)
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func load() {
        let categoryId = category.persistentModelID
        let calendar = Calendar.current
        let monthStart = Budget.normalize(month)
        let monthEnd = calendar.date(byAdding: DateComponents(month: 1), to: monthStart) ?? monthStart

        let descriptor = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let all = (try? modelContext.fetch(descriptor)) ?? []
        transactions = all.filter { transaction in
            transaction.date >= monthStart
                && transaction.date < monthEnd
                && transaction.category?.persistentModelID == categoryId
                && transaction.countsTowardTotals
        }
    }
}
