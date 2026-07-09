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
