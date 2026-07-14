import Foundation
import Observation
import SwiftData

/// Drives the "Connect Wealthsimple" screen using a **direct** connection to Wealthsimple's own
/// API -- the user signs in with their Wealthsimple email/password (and 2FA) and the app reads
/// their Wealthsimple Cash account and its activity. No third-party aggregator, no API keys, no
/// paid plan; this is the free replacement for the old Plaid path.
///
/// Sync runs through `WealthsimpleSyncCoordinator` (shared with the app-level auto-sync), which
/// records last-synced/error/needs-reauth state; this view model mirrors that state for the UI.
@MainActor
@Observable
final class IntegrationsViewModel {
    enum ConnectionState: Equatable {
        case notConnected
        case connected
    }

    var email: String = ""
    var password: String = ""
    var otp: String = ""
    /// Set once Wealthsimple asks for a 2-step code; the UI reveals the OTP field and the next
    /// `connect()` retries with it.
    private(set) var needsOTP = false
    private(set) var connectionState: ConnectionState = .notConnected
    private(set) var isBusy = false
    private(set) var lastError: String?
    private(set) var lastSyncedAt: Date?
    private(set) var needsReauth = false
    private(set) var lastSyncSummary: TransactionImportService.ImportSummary?

    private let credentialStore = WealthsimpleCredentialStore()
    private let statusStore = WealthsimpleSyncStatusStore()
    private let client = WealthsimpleAPIClient()
    private let coordinator = WealthsimpleSyncCoordinator()
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        refreshState()
    }

    func refreshState() {
        lastSyncedAt = statusStore.lastSyncedAt
        needsReauth = statusStore.needsReauth
        connectionState = credentialStore.isConnected ? .connected : .notConnected
    }

    /// Logs in and, on success, kicks off the first sync. If Wealthsimple asks for a 2-step code,
    /// `needsOTP` flips on and the user is prompted to enter it and tap Connect again.
    func connect() async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            lastError = "Enter your Wealthsimple email and password."
            return
        }

        isBusy = true
        lastError = nil
        defer { isBusy = false }

        let otpAnswer = needsOTP ? otp.trimmingCharacters(in: .whitespacesAndNewlines) : nil

        do {
            let session = try await client.logIn(email: trimmedEmail, password: password, otp: otpAnswer)
            credentialStore.session = session
            statusStore.recordSuccess()
            // Clear the entered secrets from memory now that we hold a token instead.
            password = ""
            otp = ""
            needsOTP = false
            refreshState()
            await sync()
        } catch WealthsimpleAPIClient.ClientError.otpRequired {
            needsOTP = true
            lastError = "Enter the 2-step verification code Wealthsimple just sent you."
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func sync() async {
        isBusy = true
        lastError = nil
        defer { isBusy = false }

        // Import on a background context so the sync's SQLite I/O stays off the main thread.
        let importer = TransactionSyncActor(modelContainer: modelContext.container)
        switch await coordinator.sync(using: importer) {
        case .notConnected:
            lastError = "Connect Wealthsimple first."
        case .success(let summary):
            lastSyncSummary = summary
        case .needsReauth:
            break // surfaced via `needsReauth` after refreshState()
        case .failure(let message):
            lastError = message
        }
        refreshState()
    }

    func disconnect() {
        credentialStore.disconnect()
        statusStore.clear()
        lastSyncSummary = nil
        needsOTP = false
        refreshState()
    }
}
