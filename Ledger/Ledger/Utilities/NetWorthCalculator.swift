import Foundation

enum NetWorthCalculator {
    struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let value: Decimal
    }

    /// Net worth at any instant = Σ(account starting balances) + Σ(transaction amounts on or before that instant).
    /// Because an account's current balance is its starting balance plus all its transactions, summing across
    /// accounts collapses to this — no historical balance snapshots are needed.
    ///
    /// Returns one point per month boundary within `interval` (inclusive of the end), which is what the
    /// net-worth line chart plots.
    static func monthlySeries(
        accounts: [Account],
        transactions: [Transaction],
        interval: DateInterval,
        calendar: Calendar = .current
    ) -> [Point] {
        let baseline = accounts.reduce(Decimal(0)) { $0 + $1.startingBalance }
        let sortedTransactions = transactions.sorted { $0.date < $1.date }

        var boundaries: [Date] = []
        var cursor = calendar.date(from: calendar.dateComponents([.year, .month], from: interval.start)) ?? interval.start
        while cursor <= interval.end {
            boundaries.append(cursor)
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        if boundaries.last != interval.end {
            boundaries.append(interval.end)
        }

        return boundaries.map { boundary in
            let sum = sortedTransactions
                .prefix { $0.date <= boundary }
                .reduce(Decimal(0)) { $0 + $1.amount }
            return Point(date: boundary, value: baseline + sum)
        }
    }
}
