import SwiftUI
import SwiftData

/// All transactions in one category (or the uncategorized bucket) over a date range — reached by
/// tapping a budget row, a dashboard/report doughnut slice, or its legend row. Shows the range's
/// total up top, then each transaction (tap through to its detail).
struct CategoryTransactionsView: View {
    @Environment(\.modelContext) private var modelContext

    /// The category to show, or nil for the "Uncategorized" bucket (transactions with no category).
    let category: Category?
    private let interval: DateInterval
    private let subtitle: String

    @State private var transactions: [Transaction] = []

    /// Month-scoped (Budgets, Dashboard): the whole calendar month containing `month`.
    init(category: Category, month: Date) {
        self.init(category: category, interval: Self.monthInterval(month), subtitle: DateFormatting.monthYear(month))
    }

    /// The uncategorized transactions for the calendar month containing `month`.
    init(uncategorizedForMonth month: Date) {
        self.init(category: nil, interval: Self.monthInterval(month), subtitle: DateFormatting.monthYear(month))
    }

    /// Range-scoped (Reports) / designated: an arbitrary interval with a caller-supplied label.
    /// A nil `category` lists everything uncategorized in the interval.
    init(category: Category?, interval: DateInterval, subtitle: String) {
        self.category = category
        self.interval = interval
        self.subtitle = subtitle
    }

    private static func monthInterval(_ month: Date) -> DateInterval {
        let start = Budget.normalize(month)
        let end = Calendar.current.date(byAdding: DateComponents(month: 1), to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    private var title: String { category?.name ?? "Uncategorized" }
    private var symbol: String { category?.sfSymbolName ?? "questionmark.circle.fill" }
    private var color: Color { category.map { Color(hex: $0.colorHex) } ?? Color.secondary }

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
                    systemImage: symbol,
                    title: "No Transactions",
                    message: "Nothing in \(title) for \(subtitle)."
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
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .accent(.transactions)
        .accentWash(.transactions)
        .task(id: category?.persistentModelID) { load() }
    }

    private var summaryRow: some View {
        HStack {
            Image(systemName: symbol)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(color, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(subtitle)
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
                Text(CurrencyFormatter.string(from: spent))
                    .font(.appTitle2.bold())
            }
            Spacer()
            if income > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Income").font(.appCaption).foregroundStyle(.secondary)
                    Text(CurrencyFormatter.string(from: income))
                        .font(.appSubheadline.weight(.medium))
                        .foregroundStyle(Palette.income)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func load() {
        let categoryId = category?.persistentModelID
        let descriptor = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let all = (try? modelContext.fetch(descriptor)) ?? []
        transactions = all.filter { transaction in
            guard transaction.date >= interval.start, transaction.date < interval.end, transaction.countsTowardTotals else {
                return false
            }
            if let categoryId {
                return transaction.category?.persistentModelID == categoryId
            } else {
                return transaction.category == nil
            }
        }
    }
}
