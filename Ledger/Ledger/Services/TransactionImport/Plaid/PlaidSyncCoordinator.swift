import Foundation
import SwiftData

/// Headless sync of the linked Plaid connection into SwiftData, recording status as it goes.
/// Shared by the Integrations screen ("Sync Now") and the app-level auto-sync on foreground, so
/// both go through the same path and update the same `PlaidSyncStatusStore`.
@MainActor
struct PlaidSyncCoordinator {
    enum Outcome {
        case notConnected
        case success(TransactionImportService.ImportSummary)
        case needsReauth
        case failure(String)
    }

    /// Plaid item errors that mean the user must re-authenticate (Link update mode) before syncing.
    private static let reauthCodes: Set<String> = ["ITEM_LOGIN_REQUIRED", "ITEM_LOCKED", "PENDING_EXPIRATION"]

    private let credentialStore = PlaidCredentialStore()
    private let statusStore = PlaidSyncStatusStore()
    private let apiClient = PlaidAPIClient()

    var isConnected: Bool { credentialStore.isConnected }
    var lastSyncedAt: Date? { statusStore.lastSyncedAt }

    @discardableResult
    func sync(modelContext: ModelContext) async -> Outcome {
        guard let credentials = credentialStore.snapshot else { return .notConnected }

        do {
            // `/transactions/get` serves Plaid's *cached* copy of the bank data, which Plaid only
            // re-pulls from the institution a few times a day on its own. Request an on-demand
            // refresh first so a transaction that just happened can make it into this sync.
            // Best-effort: the endpoint is a Plaid add-on, so a failure (not enabled, rate
            // limited) must not block the sync — we still import whatever Plaid already has, and
            // the periodic re-sync picks up anything the refresh surfaces late.
            if (try? await apiClient.refreshTransactions(credentials: credentials)) != nil {
                try? await Task.sleep(for: .seconds(4))
            }

            let source = PlaidTransactionSource(credentials: credentials, client: apiClient)
            let importService = TransactionImportService(modelContext: modelContext)
            let summary = try await importService.importAll(from: source, sourceKind: .plaid)
            statusStore.recordSuccess()
            return .success(summary)
        } catch let error as PlaidAPIClient.ClientError {
            if case .server(_, let code?, _) = error, Self.reauthCodes.contains(code) {
                statusStore.recordNeedsReauth()
                return .needsReauth
            }
            statusStore.recordFailure(error.localizedDescription)
            return .failure(error.localizedDescription)
        } catch {
            statusStore.recordFailure(error.localizedDescription)
            return .failure(error.localizedDescription)
        }
    }
}
