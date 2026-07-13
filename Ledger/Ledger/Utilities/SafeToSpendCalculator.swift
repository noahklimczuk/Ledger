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
                    && !billNames.contains(series.displayName.lowercased().trimmingCharacters(in: .whitespaces))
            }
            .reduce(Decimal(0)) { total, series in
                total + Decimal(occurrences(of: series, from: now, before: monthEnd, calendar: calendar)) * (-series.averageAmount)
            }

        return billTotal + recurringTotal
    }

    /// Expected hits of a recurring series in `[from, before)` — a weekly charge late in the
    /// month can land several more times before month end, and each one needs reserving.
    private static func occurrences(of series: RecurringSeries, from: Date, before end: Date, calendar: Calendar) -> Int {
        var next = series.nextExpected
        var guardCounter = 0
        // Roll a stale next-expected forward to the window first.
        while next < from && guardCounter < 24 {
            next = series.cadence.nextDate(after: next, calendar: calendar)
            guardCounter += 1
        }
        var count = 0
        while next < end && count < 24 {
            count += 1
            next = series.cadence.nextDate(after: next, calendar: calendar)
        }
        return count
    }
}
