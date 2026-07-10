import Foundation
import Testing
@testable import Ledger

struct DebtPayoffCalculatorTests {
    @Test func zeroInterestIsStraightDivision() {
        let projection = DebtPayoffCalculator.project(balance: 1000, annualInterestRate: 0, monthlyPayment: 100)
        #expect(projection?.months == 10)
        #expect(projection?.totalInterest == 0)
    }

    @Test func paymentBelowInterestNeverPaysOff() {
        // 19.99% APR on $10,000 accrues ~$166/month — a $100 payment can't win.
        #expect(DebtPayoffCalculator.project(balance: 10000, annualInterestRate: 19.99, monthlyPayment: 100) == nil)
    }

    @Test func amortizationMatchesKnownCase() {
        // $5,000 at 12% APR, $500/month → 10.59 payments, rounded up to 11. The calculator
        // treats the final month as a full payment, so interest = 500 × 11 − 5000.
        let projection = DebtPayoffCalculator.project(balance: 5000, annualInterestRate: 12, monthlyPayment: 500)
        #expect(projection?.months == 11)
        #expect(projection?.totalInterest == 500)
    }

    @Test func zeroBalanceIsAlreadyPaid() {
        let projection = DebtPayoffCalculator.project(balance: 0, annualInterestRate: 10, monthlyPayment: 0)
        #expect(projection?.months == 0)
    }
}

@MainActor
struct SafeToSpendTests {
    private func makeSeries(amount: Decimal, cadence: RecurrenceCadence, next: Date) -> RecurringSeries {
        RecurringSeries(
            merchantKey: "series-\(cadence.rawValue)-\(amount)",
            displayName: "Series",
            averageAmount: amount,
            cadence: cadence,
            lastOccurrence: next,
            nextExpected: next,
            occurrenceCount: 5
        )
    }

    @Test func weeklySeriesReservesEveryOccurrenceBeforeMonthEnd() {
        let calendar = Calendar(identifier: .gregorian)
        // "Now" = March 1, 2026; weekly $10 due March 2 → 5 hits before April 1 (2, 9, 16, 23, 30).
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let first = calendar.date(from: DateComponents(year: 2026, month: 3, day: 2))!
        let series = makeSeries(amount: -10, cadence: .weekly, next: first)

        let reserved = SafeToSpendCalculator.upcomingCommitments(bills: [], recurring: [series], now: now, calendar: calendar)
        #expect(reserved == 50)
    }

    @Test func billWithSameNameIsNotDoubleCounted() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let due = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10))!

        let bill = BillReminder(name: "Rent", amount: 2000, dueDate: due)
        let series = RecurringSeries(
            merchantKey: "rent",
            displayName: "Rent",
            averageAmount: -2000,
            cadence: .monthly,
            lastOccurrence: due,
            nextExpected: due,
            occurrenceCount: 6
        )

        let reserved = SafeToSpendCalculator.upcomingCommitments(bills: [bill], recurring: [series], now: now, calendar: calendar)
        #expect(reserved == 2000)
    }

    @Test func incomeAndIgnoredSeriesAreExcluded() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let due = calendar.date(from: DateComponents(year: 2026, month: 3, day: 5))!

        let income = makeSeries(amount: 2500, cadence: .biweekly, next: due)
        let ignored = makeSeries(amount: -99, cadence: .monthly, next: due)
        ignored.isIgnored = true

        let reserved = SafeToSpendCalculator.upcomingCommitments(bills: [], recurring: [income, ignored], now: now, calendar: calendar)
        #expect(reserved == 0)
    }
}

struct NetWorthCalculatorTests {
    @Test func seriesAccumulatesTransactionsUpToEachBoundary() {
        let calendar = Calendar(identifier: .gregorian)
        let jan1 = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let feb1 = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        let mar1 = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!

        let account = Account(name: "Chequing", type: .chequing, startingBalance: 1000)
        let january = Transaction(date: calendar.date(from: DateComponents(year: 2026, month: 1, day: 10))!, merchant: "Pay", amount: 500, account: nil)
        let february = Transaction(date: calendar.date(from: DateComponents(year: 2026, month: 2, day: 10))!, merchant: "Rent", amount: -300, account: nil)

        let points = NetWorthCalculator.monthlySeries(
            accounts: [account],
            transactions: [january, february],
            interval: DateInterval(start: jan1, end: mar1),
            calendar: calendar
        )

        #expect(points.count == 3)
        #expect(points[0].value == 1000)   // Jan 1: nothing yet
        #expect(points[1].value == 1500)   // Feb 1: +500 pay
        #expect(points[2].value == 1200)   // Mar 1: -300 rent
    }
}
