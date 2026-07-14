import Foundation
import SwiftData

/// Headless sync of the linked Wealthsimple connection into SwiftData, recording status as it
/// goes. Shared by the Integrations screen ("Sync Now") and the app-level auto-sync on foreground,
/// so both go through the same path and update the same `WealthsimpleSyncStatusStore`.
@MainActor
struct WealthsimpleSyncCoordinator {
    enum Outcome {
        case notConnected
        case success(TransactionImportService.ImportSummary)
        case needsReauth
        case failure(String)
    }

    private let credentialStore = WealthsimpleCredentialStore()
    private let statusStore = WealthsimpleSyncStatusStore()
    private let client = WealthsimpleAPIClient()

    var isConnected: Bool { credentialStore.isConnected }
    var lastSyncedAt: Date? { statusStore.lastSyncedAt }

    @discardableResult
    func sync(using importer: TransactionSyncActor) async -> Outcome {
        guard let session = credentialStore.session else { return .notConnected }

        do {
            let (authedSession, identityId) = try await authenticated(session)
            // Persist any refreshed tokens / freshly resolved identity so the next sync is cheaper.
            credentialStore.session = authedSession

            // Auth is a main-actor/network step; the DB-heavy import runs on the actor's background
            // context so SwiftData's SQLite work stays off the main thread.
            let source = WealthsimpleTransactionSource(client: client, session: authedSession, identityId: identityId)
            let summary = try await importer.importAll(from: source, sourceKind: .wealthsimple)
            statusStore.recordSuccess()
            return .success(summary)
        } catch WealthsimpleAPIClient.ClientError.reauthRequired {
            statusStore.recordNeedsReauth()
            return .needsReauth
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusStore.recordFailure(message)
            return .failure(message)
        }
    }

    /// Returns a session with a valid access token plus the resolved identity id, refreshing the
    /// token (once) if it has lapsed. Throws `.reauthRequired` when the refresh token is dead.
    private func authenticated(_ session: WealthsimpleSession) async throws -> (WealthsimpleSession, String) {
        do {
            let id = try await client.identityId(for: session)
            var updated = session
            updated.identityId = id
            return (updated, id)
        } catch WealthsimpleAPIClient.ClientError.server(let status, _) where status == 401 {
            // Access token expired -- refresh and retry once.
            let refreshed = try await client.refreshedSession(session)
            let id = try await client.identityId(for: refreshed)
            var updated = refreshed
            updated.identityId = id
            return (updated, id)
        }
    }
}
