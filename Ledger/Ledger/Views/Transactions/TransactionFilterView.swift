import SwiftUI
import SwiftData

struct TransactionFilterView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Binding var filter: TransactionFilter

    @State private var accounts: [Account] = []
    @State private var categories: [Category] = []
    @State private var useDateRange = false
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
                Section {
                    Toggle("Date Range", isOn: $useDateRange)
                    if useDateRange {
                        DatePicker("From", selection: $startDate, displayedComponents: .date)
                        DatePicker("To", selection: $endDate, displayedComponents: .date)
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

    private func load() {
        accounts = (try? modelContext.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.name)]))) ?? []
        categories = (try? modelContext.fetch(FetchDescriptor<Category>(sortBy: [SortDescriptor(\.name)]))) ?? []
        useDateRange = filter.startDate != nil || filter.endDate != nil
        useAmountRange = filter.minAmount != nil || filter.maxAmount != nil
        startDate = filter.startDate ?? .now
        endDate = filter.endDate ?? .now
        minAmountText = filter.minAmount.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
        maxAmountText = filter.maxAmount.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
    }

    private func apply() {
        filter.startDate = useDateRange ? startDate : nil
        filter.endDate = useDateRange ? endDate : nil
        filter.minAmount = useAmountRange ? ImportValueParsing.decimal(from: minAmountText) : nil
        filter.maxAmount = useAmountRange ? ImportValueParsing.decimal(from: maxAmountText) : nil
    }
}
