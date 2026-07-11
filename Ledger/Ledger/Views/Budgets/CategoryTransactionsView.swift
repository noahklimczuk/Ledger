import SwiftUI
import SwiftData

/// All transactions in one category over a date range — reached by tapping a budget row, a
/// dashboard/report doughnut slice, or its legend row. Shows the range's total for the category up
/// top, then each transaction (tap through to its detail).
struct CategoryTransactionsView: View {
    @Environment(\.modelContext) private var modelContext

    let category: Category
    private let interval: DateInterval
    private let subtitle: String

    @State private var transactions: [Transaction] = []

    /// Month-scoped (Budgets, Dashboard): the whole calendar month containing `month`.
    init(category: Category, month: Date) {
        let monthStart = Budget.normalize(month)
        let monthEnd = Calendar.current.date(byAdding: DateComponents(month: 1), to: monthStart) ?? monthStart
        self.init(
            category: category,
            interval: DateInterval(start: monthStart, end: monthEnd),
            subtitle: DateFormatting.monthYear(month)
        )
    }

    /// Range-scoped (Reports): an arbitrary interval with a caller-supplied label.
    init(category: Category, interval: DateInterval, subtitle: String) {
        self.category = category
        self.interval = interval
        self.subtitle = subtitle
    }

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
                    message: "Nothing in \(category.name) for \(subtitle)."
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
    }

    private var summaryRow: some View {
        HStack {
            Image(systemName: category.sfSymbolName)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color(hex: category.colorHex), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(subtitle)
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
        let descriptor = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let all = (try? modelContext.fetch(descriptor)) ?? []
        transactions = all.filter { transaction in
            transaction.date >= interval.start
                && transaction.date < interval.end
                && transaction.category?.persistentModelID == categoryId
                && transaction.countsTowardTotals
        }
    }
}
