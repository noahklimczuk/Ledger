import SwiftUI
import SwiftData

struct BillReminderEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let reminder: BillReminder?

    @State private var name = ""
    @State private var amountText = ""
    @State private var dueDate = Date()
    @State private var isRecurring = false
    @State private var cadence: RecurrenceCadence = .monthly
    @State private var notifyDaysBefore = 1

    var body: some View {
        NavigationStack {
            Form {
                Section("Bill") {
                    TextField("Name", text: $name)
                    TextField("Amount", text: $amountText).keyboardType(.decimalPad)
                    DatePicker("Due date", selection: $dueDate, displayedComponents: .date)
                }
                Section("Repeat") {
                    Toggle("Recurring", isOn: $isRecurring)
                    if isRecurring {
                        Picker("Frequency", selection: $cadence) {
                            ForEach(RecurrenceCadence.allCases) { cadence in
                                Text(cadence.displayName).tag(cadence)
                            }
                        }
                    }
                }
                Section("Reminder") {
                    Stepper("Notify \(notifyDaysBefore) day\(notifyDaysBefore == 1 ? "" : "s") before", value: $notifyDaysBefore, in: 0...30)
                }
            }
            .navigationTitle(reminder == nil ? "New Bill" : "Edit Bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || ImportValueParsing.decimal(from: amountText) == nil)
                }
            }
            .onAppear(perform: populate)
        }
    }

    private func populate() {
        guard let reminder else { return }
        name = reminder.name
        amountText = NSDecimalNumber(decimal: reminder.amount).stringValue
        dueDate = reminder.dueDate
        notifyDaysBefore = reminder.notifyDaysBefore
        if let cadence = reminder.cadence {
            isRecurring = true
            self.cadence = cadence
        }
    }

    private func save() {
        guard let amount = ImportValueParsing.decimal(from: amountText) else { return }
        let selectedCadence = isRecurring ? cadence : nil
        let viewModel = BillRemindersViewModel(modelContext: modelContext)

        Task {
            if let reminder {
                await viewModel.updateReminder(reminder, name: name, amount: amount, dueDate: dueDate, cadence: selectedCadence, notifyDaysBefore: notifyDaysBefore)
            } else {
                await viewModel.addReminder(name: name, amount: amount, dueDate: dueDate, cadence: selectedCadence, notifyDaysBefore: notifyDaysBefore)
            }
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
