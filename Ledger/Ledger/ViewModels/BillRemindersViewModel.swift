import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class BillRemindersViewModel {
    private(set) var reminders: [BillReminder] = []
    private(set) var notificationsDenied = false

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func load() {
        let descriptor = FetchDescriptor<BillReminder>(sortBy: [SortDescriptor(\.dueDate)])
        reminders = (try? modelContext.fetch(descriptor)) ?? []
    }

    func addReminder(name: String, amount: Decimal, dueDate: Date, cadence: RecurrenceCadence?, notifyDaysBefore: Int) async {
        await ensureAuthorization()
        let reminder = BillReminder(name: name, amount: amount, dueDate: dueDate, cadence: cadence, notifyDaysBefore: notifyDaysBefore)
        modelContext.insert(reminder)
        try? modelContext.save()
        await NotificationService.schedule(reminder)
        load()
    }

    func updateReminder(_ reminder: BillReminder, name: String, amount: Decimal, dueDate: Date, cadence: RecurrenceCadence?, notifyDaysBefore: Int) async {
        reminder.name = name
        reminder.amount = amount
        reminder.dueDate = dueDate
        reminder.cadence = cadence
        reminder.notifyDaysBefore = notifyDaysBefore
        try? modelContext.save()
        await NotificationService.schedule(reminder)
        load()
    }

    func setEnabled(_ reminder: BillReminder, enabled: Bool) async {
        reminder.isEnabled = enabled
        try? modelContext.save()
        if enabled {
            await ensureAuthorization()
            await NotificationService.schedule(reminder)
        } else {
            NotificationService.cancel(reminder)
        }
        load()
    }

    /// Advances a recurring bill to its next due date (e.g. after paying it) and reschedules.
    func markPaidAndAdvance(_ reminder: BillReminder) async {
        guard let cadence = reminder.cadence else { return }
        reminder.dueDate = cadence.nextDate(after: reminder.dueDate)
        try? modelContext.save()
        await NotificationService.schedule(reminder)
        load()
    }

    func delete(_ reminder: BillReminder) {
        NotificationService.cancel(reminder)
        modelContext.delete(reminder)
        try? modelContext.save()
        load()
    }

    private func ensureAuthorization() async {
        let granted = await NotificationService.requestAuthorization()
        notificationsDenied = !granted
    }
}
