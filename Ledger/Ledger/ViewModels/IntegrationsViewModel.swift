import Foundation
import Observation
import SwiftData

/// Drives the "Connect Wealthsimple" screen using **Plaid** (a bank-account aggregator), so the
/// accounts pulled in are Wealthsimple *Cash*/chequing/savings -- the bank side -- rather than
/// brokerage/trading accounts. Plaid slots in behind the shared `TransactionSource` seam.
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
    private(set) var lastSyncSummary: TransactionImportService.ImportSummary?

    private let credentialStore = PlaidCredentialStore()
    private let apiClient = PlaidAPIClient()
    private let connectSession = PlaidConnectSession()
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
            refreshState()
            await sync()
        } catch PlaidConnectSession.ConnectError.cancelled {
            // User backed out of Plaid Link; nothing to surface as an error.
        } catch {
            lastError = error.localizedDescription
        }
    }

    func sync() async {
        guard let credentials = credentialStore.snapshot else {
            lastError = "Connect Wealthsimple first."
            return
        }

        isBusy = true
        lastError = nil
        defer { isBusy = false }

        do {
            let source = PlaidTransactionSource(credentials: credentials, client: apiClient)
            let importService = TransactionImportService(modelContext: modelContext)
            lastSyncSummary = try await importService.importAll(from: source, sourceKind: .plaid)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func disconnect() {
        credentialStore.disconnect()
        refreshState()
    }
}
