import SwiftUI
import SwiftData

struct TransactionFilterView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Binding var filter: TransactionFilter

    @State private var accounts: [Account] = []
    @State private var categories: [Category] = []
    // Start and end are independent optional bounds, not one coupled range. Coupling them behind a
    // single "Date Range" toggle meant every applied date filter also stamped an end date — and that
    // end date, frozen at whatever "today" was when it was set and persisted across launches, quietly
    // became a ceiling that hid every newer transaction. So the list looked like it had "stopped
    // updating" while balances and every other screen (which ignore the filter) kept moving.
    @State private var useStartDate = false
    @State private var useEndDate = false
    @State private var useAmountRange = false
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var minAmountText = ""
    @State private var maxAmountText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Type", selection: $filter.kind) {
                        ForEach(TransactionFilter.Kind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Status") {
                    Picker("Status", selection: $filter.reviewState) {
                        ForEach(TransactionFilter.ReviewState.allCases) { state in
                            Text(state.label).tag(state)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Account") {
                    Picker("Account", selection: $filter.account) {
                        Text("Any").tag(Account?.none)
                        ForEach(accounts) { account in
                            Text(account.name).tag(Account?.some(account))
                        }
                    }
                }
                Section("Category") {
                    Picker("Category", selection: $filter.category) {
                        Text("Any").tag(Category?.none)
                        ForEach(categories) { category in
                            Text(category.name).tag(Category?.some(category))
                        }
                    }
                }
                Section("Date") {
                    Toggle("From Date", isOn: $useStartDate)
                    if useStartDate {
                        DatePicker("From", selection: $startDate, displayedComponents: .date)
                    }
                    Toggle("To Date", isOn: $useEndDate)
                    if useEndDate {
                        DatePicker("To", selection: $endDate, displayedComponents: .date)
                    }
                    // Quick preset: everything since Jan 1, with no end cap — so the list keeps
                    // surfacing new transactions as they sync in rather than freezing at "today".
                    Button {
                        useStartDate = true
                        startDate = Self.startOfYear
                        useEndDate = false
                    } label: {
                        Label("Year to Date", systemImage: "calendar")
                    }
                }
                Section {
                    Toggle("Amount Range", isOn: $useAmountRange)
                    if useAmountRange {
                        TextField("Min", text: $minAmountText).keyboardType(.decimalPad)
                        TextField("Max", text: $maxAmountText).keyboardType(.decimalPad)
                    }
                }
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        filter = TransactionFilter()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { apply(); dismiss() }
                }
            }
            .task { load() }
        }
    }

    /// Midnight on January 1 of the current year — the start of the year-to-date window.
    private static var startOfYear: Date {
        let calendar = Calendar.current
        return calendar.date(from: calendar.dateComponents([.year], from: .now)) ?? .now
    }

    private func load() {
        accounts = (try? modelContext.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.name)]))) ?? []
        categories = (try? modelContext.fetch(FetchDescriptor<Category>(sortBy: [SortDescriptor(\.name)]))) ?? []
        useStartDate = filter.startDate != nil
        useEndDate = filter.endDate != nil
        useAmountRange = filter.minAmount != nil || filter.maxAmount != nil
        startDate = filter.startDate ?? .now
        endDate = filter.endDate ?? .now
        minAmountText = filter.minAmount.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
        maxAmountText = filter.maxAmount.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
    }

    private func apply() {
        filter.startDate = useStartDate ? Calendar.current.startOfDay(for: startDate) : nil
        filter.endDate = useEndDate ? endDate : nil
        filter.minAmount = useAmountRange ? ImportValueParsing.decimal(from: minAmountText) : nil
        filter.maxAmount = useAmountRange ? ImportValueParsing.decimal(from: maxAmountText) : nil
    }
}
