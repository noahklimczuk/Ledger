import Foundation
import Observation
import SwiftData

/// Backs the 2-minute daily check-in ritual: catch up on unreviewed transactions, see which
/// budgets drifted, confirm the money already spoken for, and re-zero the plan. Tracks when the
/// ritual last happened so the Dashboard can nudge on days it hasn't been done yet.
@MainActor
@Observable
final class DailyCheckInViewModel {
    private enum Key {
        static let lastCompletedAt = "checkIn.lastCompletedAt"
        static let dailyReminderEnabled = "checkIn.dailyReminderEnabled"
        /// Pre-daily-cadence flag; read as a fallback so upgraders keep their opt-in.
        static let legacyWeeklyReminderEnabled = "checkIn.weeklyReminderEnabled"
    }

    private(set) var unreviewed: [Transaction] = []
    private(set) var reviewedThisSession = 0
    private(set) var overBudget: [BudgetsViewModel.BudgetRow] = []
    private(set) var aheadOfPace: [BudgetsViewModel.BudgetRow] = []
    private(set) var upcomingBills: [BillReminder] = []
    private(set) var leftToAssign: Decimal = 0
    private(set) var incomeToAssign: Decimal = 0
    private(set) var monthProgress: Double = 0

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    var upcomingBillsTotal: Decimal {
        upcomingBills.reduce(Decimal(0)) { $0 + $1.amount }
    }

    /// Due whenever today's check-in hasn't happened yet.
    static func isDue(now: Date = .now) -> Bool {
        guard let last = UserDefaults.standard.object(forKey: Key.lastCompletedAt) as? Date else { return true }
        return !Calendar.current.isDate(last, inSameDayAs: now)
    }

    static var dailyReminderEnabled: Bool {
        let defaults = UserDefaults.standard
        return defaults.bool(forKey: Key.dailyReminderEnabled) || defaults.bool(forKey: Key.legacyWeeklyReminderEnabled)
    }

    func load() {
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { !$0.isReviewed },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        unreviewed = ((try? modelContext.fetch(descriptor)) ?? []).filter(\.countsTowardTotals)

        let budgets = BudgetsViewModel(modelContext: modelContext)
        budgets.selectedMonth = Budget.normalize(.now)
        overBudget = budgets.rows.filter(\.isOverBudget)
        // "Drifting" rather than broken: not over yet, but the bar is meaningfully past the
        // month-pace tick.
        aheadOfPace = budgets.rows.filter { !$0.isOverBudget && budgets.monthProgress > 0.1 && $0.progress > budgets.monthProgress + 0.1 }
        leftToAssign = budgets.leftToAssign
        incomeToAssign = budgets.incomeToAssign
        monthProgress = budgets.monthProgress

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let horizon = calendar.date(byAdding: .day, value: 14, to: today) ?? today
        let bills = (try? modelContext.fetch(FetchDescriptor<BillReminder>(sortBy: [SortDescriptor(\.dueDate)]))) ?? []
        upcomingBills = bills.filter { $0.dueDate < horizon }
    }

    func markReviewed(_ transaction: Transaction) {
        transaction.isReviewed = true
        try? modelContext.save()
        reviewedThisSession += 1
        unreviewed.removeAll { $0.persistentModelID == transaction.persistentModelID }
    }

    func markAllReviewed() {
        for transaction in unreviewed {
            transaction.isReviewed = true
        }
        try? modelContext.save()
        reviewedThisSession += unreviewed.count
        unreviewed = []
    }

    func complete(dailyReminder: Bool) async {
        let defaults = UserDefaults.standard
        defaults.set(Date(), forKey: Key.lastCompletedAt)
        defaults.set(dailyReminder, forKey: Key.dailyReminderEnabled)
        defaults.removeObject(forKey: Key.legacyWeeklyReminderEnabled)
        if dailyReminder {
            _ = await NotificationService.requestAuthorization()
            await NotificationService.scheduleDailyCheckIn()
        } else {
            NotificationService.cancelDailyCheckIn()
        }
    }
}
