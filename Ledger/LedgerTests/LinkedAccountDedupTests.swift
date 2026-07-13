import Foundation
import SwiftData
import Testing
@testable import Ledger

/// A stand-in `TransactionSource` (like the Wealthsimple sync) that returns a fixed account and
/// its transactions, so the import service's account de-duplication can be tested end-to-end.
private struct MockSource: TransactionSource {
    let sourceIdentifier: String
    let accounts: [ImportedAccount]
    let transactionsByAccount: [String: [ImportedTransaction]]

    func fetchAccounts() async throws -> [ImportedAccount] { accounts }

    func fetchTransactions(accountExternalId: String, since: Date?) async throws -> [ImportedTransaction] {
        transactionsByAccount[accountExternalId] ?? []
    }
}

@MainActor
struct LinkedAccountDedupTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema(LedgerSchema.models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration]).mainContext
    }

    private func source() -> MockSource {
        let account = ImportedAccount(
            id: "cash-1",
            name: "Wealthsimple Cash",
            institutionName: "Wealthsimple",
            type: .chequing,
            currencyCode: "CAD",
            currentBalance: 100
        )
        let transactions = [
            ImportedTransaction(id: "t1", accountExternalId: "cash-1", date: .now, merchant: "A", amount: -10, currencyCode: "CAD"),
            ImportedTransaction(id: "t2", accountExternalId: "cash-1", date: .now, merchant: "B", amount: -20, currencyCode: "CAD"),
        ]
        return MockSource(sourceIdentifier: "wealthsimple", accounts: [account], transactionsByAccount: ["cash-1": transactions])
    }

    @Test func resyncDoesNotCreateDuplicateAccounts() async throws {
        let context = try makeContext()
        let service = TransactionImportService(modelContext: context)

        _ = try await service.importAll(from: source(), sourceKind: .wealthsimple)
        _ = try await service.importAll(from: source(), sourceKind: .wealthsimple)

        let accounts = try context.fetch(FetchDescriptor<Account>())
        #expect(accounts.count == 1)
        #expect(accounts.first?.transactions.count == 2)
    }

    @Test func mergesPreexistingDuplicateAccounts() async throws {
        let context = try makeContext()

        // Reproduce the bug's aftermath: two linked accounts sharing the same external ids, with
        // the real transactions on one and an empty duplicate alongside it.
        let real = Account(name: "Wealthsimple Cash", type: .chequing, externalSourceId: "wealthsimple", externalAccountId: "cash-1")
        context.insert(real)
        context.insert(Transaction(date: .now, merchant: "A", amount: -10, account: real, sourceKind: .wealthsimple, externalId: "t1"))
        let duplicate = Account(name: "Wealthsimple Cash", type: .chequing, externalSourceId: "wealthsimple", externalAccountId: "cash-1")
        context.insert(duplicate)
        try context.save()

        _ = try await TransactionImportService(modelContext: context).importAll(from: source(), sourceKind: .wealthsimple)

        let accounts = try context.fetch(FetchDescriptor<Account>())
        #expect(accounts.count == 1)
        // t1 was already present; the sync adds t2. No transaction is duplicated.
        #expect(accounts.first?.transactions.count == 2)
    }

    @Test func leavesUnrelatedManualAccountsAlone() async throws {
        let context = try makeContext()
        let manual = Account(name: "Cash Wallet", type: .chequing)
        context.insert(manual)
        try context.save()

        _ = try await TransactionImportService(modelContext: context).importAll(from: source(), sourceKind: .wealthsimple)

        let accounts = try context.fetch(FetchDescriptor<Account>())
        // The manual account plus the one linked account — the manual one is never merged away.
        #expect(accounts.count == 2)
    }
}
