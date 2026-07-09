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
        // Only show accounts the user is actively tracking. Archived accounts stay in the store
        // (so a linked account can't be re-created by the next Plaid sync) but are hidden here.
        let descriptor = FetchDescriptor<Account>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.name)]
        )
        accounts = (try? modelContext.fetch(descriptor)) ?? []
    }

    // Add/update persist but deliberately do NOT reload here: they're driven from the edit sheet,
    // and reloading (which re-sorts `accounts`) while that sheet is still presented mutates the
    // list's data source mid-presentation. The list reloads on the sheet's `onDismiss` instead.
    func addAccount(name: String, type: AccountType, institutionName: String?, startingBalance: Decimal) {
        let account = Account(name: name, type: type, institutionName: institutionName, startingBalance: startingBalance)
        modelContext.insert(account)
        try? modelContext.save()
    }

    func updateAccount(_ account: Account, name: String, type: AccountType, institutionName: String?, startingBalance: Decimal) {
        account.name = name
        account.type = type
        account.institutionName = institutionName
        account.startingBalance = startingBalance
        try? modelContext.save()
    }

    func archive(_ account: Account) {
        account.isArchived = true
        save()
    }

    /// Removes an account the user no longer wants to track. A purely manual account is deleted
    /// outright; a linked (Plaid) account is archived instead — deleting it would let the next sync
    /// re-create it from the institution, which is exactly the "deleted accounts come back" bug.
    /// Archiving keeps the row for dedup but hides it and excludes it from future syncs.
    func remove(_ account: Account) {
        if account.isLinked {
            account.isArchived = true
        } else {
            modelContext.delete(account)
        }
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
