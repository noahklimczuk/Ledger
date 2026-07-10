import Foundation

enum SafeToSpendCalculator {
    /// income - committed bills - budget allocations - goal contributions.
    static func calculate(
        income: Decimal,
        budgetAllocations: Decimal,
        committedBills: Decimal = 0,
        goalContributions: Decimal = 0
    ) -> Decimal {
        income - committedBills - budgetAllocations - goalContributions
    }

    /// Money already spoken for before the month ends: bill reminders due this month that haven't
    /// been paid yet (paying a recurring bill advances its due date past the window), plus
    /// auto-detected recurring charges expected between now and month end. A detected series that
    /// duplicates a bill reminder (same name) is skipped so the charge isn't reserved twice.
    ///
    /// Deliberately *not* cross-checked against budget allocations — bills have no category link,
    /// so a rent bill inside a budgeted Housing category can be reserved twice. Zero-based plans
    /// budget their bills, so keep bill reminders for the un-budgeted fixed costs.
    static func upcomingCommitments(
        bills: [BillReminder],
        recurring: [RecurringSeries],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Decimal {
        let monthStart = Budget.normalize(now)
        guard let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return 0 }

        let dueBills = bills.filter { $0.dueDate >= monthStart && $0.dueDate < monthEnd }
        let billTotal = dueBills.reduce(Decimal(0)) { $0 + $1.amount }

        let billNames = Set(dueBills.map { $0.name.lowercased().trimmingCharacters(in: .whitespaces) })
        let recurringTotal = recurring
            .filter { series in
                !series.isIgnored
                    && !series.isIncome
                    && series.nextExpected >= now && series.nextExpected < monthEnd
                    && !billNames.contains(series.displayName.lowercased().trimmingCharacters(in: .whitespaces))
            }
            .reduce(Decimal(0)) { $0 + (-$1.averageAmount) }

        return billTotal + recurringTotal
    }
}
