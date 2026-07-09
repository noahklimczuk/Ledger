import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AccountsViewModel {
    private(set) var accounts: [Account] = []
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func load() {
        let descriptor = FetchDescriptor<Account>(sortBy: [SortDescriptor(\.name)])
        accounts = (try? modelContext.fetch(descriptor)) ?? []
    }

    func addAccount(name: String, type: AccountType, institutionName: String?, startingBalance: Decimal) {
        let account = Account(name: name, type: type, institutionName: institutionName, startingBalance: startingBalance)
        modelContext.insert(account)
        save()
    }

    func updateAccount(_ account: Account, name: String, type: AccountType, institutionName: String?, startingBalance: Decimal) {
        account.name = name
        account.type = type
        account.institutionName = institutionName
        account.startingBalance = startingBalance
        save()
    }

    func archive(_ account: Account) {
        account.isArchived = true
        save()
    }

    func delete(_ account: Account) {
        modelContext.delete(account)
        save()
    }

    private func save() {
        try? modelContext.save()
        load()
    }
}
