import SwiftUI
import SwiftData

struct BillRemindersView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: BillRemindersViewModel?
    @State private var isPresentingNew = false
    @State private var editingReminder: BillReminder?

    var body: some View {
        Group {
            if let viewModel {
                if viewModel.reminders.isEmpty {
                    EmptyStateView(
                        systemImage: "bell.badge",
                        title: "No Bill Reminders",
                        message: "Add a bill and Ledger will remind you before it's due with a local notification.",
                        actionTitle: "Add Bill"
                    ) {
                        isPresentingNew = true
                    }
                } else {
                    List {
                        if viewModel.notificationsDenied {
                            Section {
                                Label("Notifications are turned off. Enable them in Settings to get reminders.", systemImage: "exclamationmark.triangle")
                                    .font(.footnote)
                                    .foregroundStyle(.orange)
                            }
                        }
                        ForEach(viewModel.reminders) { reminder in
                            BillRow(reminder: reminder) { enabled in
                                Task { await viewModel.setEnabled(reminder, enabled: enabled) }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { editingReminder = reminder }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    viewModel.delete(reminder)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                if reminder.isRecurring {
                                    Button {
                                        Task { await viewModel.markPaidAndAdvance(reminder) }
                                    } label: {
                                        Label("Paid", systemImage: "checkmark")
                                    }
                                    .tint(.green)
                                }
                            }
                        }
                    }
                }
            } else {
                LoadingView()
            }
        }
        .navigationTitle("Bill Reminders")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isPresentingNew = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add Bill")
            }
        }
        .sheet(isPresented: $isPresentingNew, onDismiss: { viewModel?.load() }) {
            BillReminderEditView(reminder: nil)
        }
        .sheet(item: $editingReminder, onDismiss: { viewModel?.load() }) { reminder in
            BillReminderEditView(reminder: reminder)
        }
        .task {
            if viewModel == nil { viewModel = BillRemindersViewModel(modelContext: modelContext) }
            viewModel?.load()
        }
    }
}

private struct BillRow: View {
    let reminder: BillReminder
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.name).fontWeight(.medium)
                HStack(spacing: 4) {
                    Text("Due \(DateFormatting.medium(reminder.dueDate))")
                    if reminder.isRecurring, let cadence = reminder.cadence {
                        Text("· \(cadence.displayName)")
                    }
                }
                .font(.caption)
                .foregroundStyle(reminder.isOverdue ? Color.red : Color.secondary)
            }
            Spacer()
            Text(CurrencyFormatter.string(from: reminder.amount))
                .fontWeight(.medium)
            Toggle("", isOn: Binding(get: { reminder.isEnabled }, set: { onToggle($0) }))
                .labelsHidden()
                .accessibilityLabel("Reminders for \(reminder.name)")
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack { BillRemindersView() }
        .modelContainer(for: LedgerSchema.models, inMemory: true)
}
