import Foundation
import Observation
import SwiftData

/// Drives the "Connect Wealthsimple" screen using **Plaid** (a bank-account aggregator), so the
/// accounts pulled in are Wealthsimple *Cash*/chequing/savings -- the bank side -- rather than
/// brokerage/trading accounts. Plaid slots in behind the shared `TransactionSource` seam.
///
/// Sync itself runs through `PlaidSyncCoordinator` (shared with the app-level auto-sync), which
/// records last-synced/error/needs-reauth state; this view model mirrors that state for the UI.
@MainActor
@Observable
final class IntegrationsViewModel {
    enum ConnectionState: Equatable {
        case notConfigured
        case configuredNotConnected
        case connected
    }

    var clientId: String = ""
    var secret: String = ""
    var environment: PlaidEnvironment = .production
    private(set) var connectionState: ConnectionState = .notConfigured
    private(set) var isBusy = false
    private(set) var lastError: String?
    private(set) var lastSyncedAt: Date?
    private(set) var needsReauth = false
    private(set) var lastSyncSummary: TransactionImportService.ImportSummary?

    private let credentialStore = PlaidCredentialStore()
    private let statusStore = PlaidSyncStatusStore()
    private let apiClient = PlaidAPIClient()
    private let connectSession = PlaidConnectSession()
    private let coordinator = PlaidSyncCoordinator()
    private let modelContext: ModelContext

    private let completionRedirectURI = "ledger://plaid-callback"

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        refreshState()
    }

    func refreshState() {
        clientId = credentialStore.clientId ?? ""
        secret = credentialStore.secret ?? ""
        environment = credentialStore.environment
        lastSyncedAt = statusStore.lastSyncedAt
        needsReauth = statusStore.needsReauth
        if credentialStore.isConnected {
            connectionState = .connected
        } else if credentialStore.hasAPICredentials {
            connectionState = .configuredNotConnected
        } else {
            connectionState = .notConfigured
        }
    }

    func saveAPICredentials() {
        credentialStore.clientId = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        credentialStore.secret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        credentialStore.environment = environment
        refreshState()
    }

    func connectWealthsimple() async {
        guard let storedClientId = credentialStore.clientId, let storedSecret = credentialStore.secret else {
            lastError = "Enter your Plaid client ID and secret first."
            return
        }

        isBusy = true
        lastError = nil
        defer { isBusy = false }

        do {
            // 1. Create a Hosted Link token and open Plaid's hosted UI.
            let linkToken = try await apiClient.createLinkToken(
                clientId: storedClientId,
                secret: storedSecret,
                environment: credentialStore.environment,
                clientUserId: credentialStore.clientUserId,
                completionRedirectURI: completionRedirectURI
            )
            guard let hostedLink = linkToken.hostedLinkUrl, let hostedURL = URL(string: hostedLink) else {
                throw PlaidAPIClient.ClientError.missingLinkURL
            }
            guard let token = linkToken.linkToken else {
                throw PlaidAPIClient.ClientError.invalidResponse
            }

            // 2. Wait for the user to complete (or cancel) the flow.
            try await connectSession.connect(hostedLinkURL: hostedURL)

            // 3. Retrieve the public token the connection produced, then exchange it.
            let results = try await apiClient.linkTokenResults(
                clientId: storedClientId,
                secret: storedSecret,
                environment: credentialStore.environment,
                linkToken: token
            )
            guard let publicToken = results.firstPublicToken else {
                throw PlaidAPIClient.ClientError.noConnectionCompleted
            }

            let exchange = try await apiClient.exchangePublicToken(
                clientId: storedClientId,
                secret: storedSecret,
                environment: credentialStore.environment,
                publicToken: publicToken
            )
            guard let accessToken = exchange.accessToken else {
                throw PlaidAPIClient.ClientError.exchangeFailed
            }

            credentialStore.accessToken = accessToken
            credentialStore.itemId = exchange.itemId
            statusStore.needsReauth = false
            refreshState()
            await sync()
        } catch PlaidConnectSession.ConnectError.cancelled {
            // User backed out of Plaid Link; nothing to surface as an error.
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Re-authenticates the existing connection via Plaid Link **update mode** (used after Plaid
    /// flags `ITEM_LOGIN_REQUIRED`). The Item's access token stays valid, so there's no new token
    /// to exchange -- completing the hosted flow is enough to clear the re-auth flag.
    func reconnect() async {
        guard let storedClientId = credentialStore.clientId,
              let storedSecret = credentialStore.secret,
              let accessToken = credentialStore.accessToken else {
            lastError = "Connect Wealthsimple first."
            return
        }

        isBusy = true
        lastError = nil
        defer { isBusy = false }

        do {
            let linkToken = try await apiClient.createLinkToken(
                clientId: storedClientId,
                secret: storedSecret,
                environment: credentialStore.environment,
                clientUserId: credentialStore.clientUserId,
                completionRedirectURI: completionRedirectURI,
                accessToken: accessToken
            )
            guard let hostedLink = linkToken.hostedLinkUrl, let hostedURL = URL(string: hostedLink) else {
                throw PlaidAPIClient.ClientError.missingLinkURL
            }

            try await connectSession.connect(hostedLinkURL: hostedURL)
            statusStore.needsReauth = false
            statusStore.lastError = nil
            refreshState()
            await sync()
        } catch PlaidConnectSession.ConnectError.cancelled {
            // User backed out; leave the needs-reauth flag as it was.
        } catch {
            lastError = error.localizedDescription
        }
    }

    func sync() async {
        isBusy = true
        lastError = nil
        defer { isBusy = false }

        switch await coordinator.sync(modelContext: modelContext) {
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
        refreshState()
    }
}
