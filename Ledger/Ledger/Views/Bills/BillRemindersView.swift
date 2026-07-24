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
                        emoji: "🔔",
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
                                Text("⚠️ Notifications are turned off. Enable them in Settings to get reminders.")
                                    .font(.appFootnote)
                                    .foregroundStyle(Palette.amber)
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
                                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
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
                                    .tint(Palette.income)
                                }
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            } else {
                LoadingView()
            }
        }
        .navigationTitle("Bill Reminders")
        .accentWash(.bills)
        .accent(.bills)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isPresentingNew = true } label: { Text("➕").font(.system(size: 20)) }
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
        HStack(spacing: 14) {
            BloomRowIcon(emoji: reminder.isOverdue ? "⚠️" : "🔔", size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.name).font(.appBodyMedium)
                HStack(spacing: 4) {
                    Text("Due \(DateFormatting.medium(reminder.dueDate))")
                    if reminder.isRecurring, let cadence = reminder.cadence {
                        Text("· \(cadence.displayName)")
                    }
                }
                .font(.appCaption)
                .foregroundStyle(reminder.isOverdue ? Palette.expense : Color.secondary)
            }
            Spacer(minLength: 8)
            Text(CurrencyFormatter.string(from: reminder.amount))
                .font(.appBody.weight(.heavy))
            Toggle("", isOn: Binding(get: { reminder.isEnabled }, set: { onToggle($0) }))
                .labelsHidden()
                .accessibilityLabel("Reminders for \(reminder.name)")
        }
        .card()
        .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack { BillRemindersView() }
        .modelContainer(for: LedgerSchema.models, inMemory: true)
}
