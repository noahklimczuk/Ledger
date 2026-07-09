import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class IntegrationsViewModel {
    enum ConnectionState: Equatable {
        case notConfigured
        case configuredNotConnected
        case connected
    }

    var clientId: String = ""
    var consumerKey: String = ""
    private(set) var connectionState: ConnectionState = .notConfigured
    private(set) var isBusy = false
    private(set) var lastError: String?
    private(set) var lastSyncSummary: TransactionImportService.ImportSummary?

    private let credentialStore = SnapTradeCredentialStore()
    private let apiClient = SnapTradeAPIClient()
    private let connectSession = SnapTradeConnectSession()
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        refreshState()
    }

    func refreshState() {
        clientId = credentialStore.clientId ?? ""
        consumerKey = credentialStore.consumerKey ?? ""
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
        credentialStore.consumerKey = consumerKey.trimmingCharacters(in: .whitespacesAndNewlines)
        refreshState()
    }

    func connectWealthsimple() async {
        guard let storedClientId = credentialStore.clientId, let storedConsumerKey = credentialStore.consumerKey else {
            lastError = "Enter your SnapTrade clientId and consumerKey first."
            return
        }

        isBusy = true
        lastError = nil
        defer { isBusy = false }

        do {
            if credentialStore.userSecret == nil {
                let registration = try await apiClient.registerUser(
                    clientId: storedClientId,
                    consumerKey: storedConsumerKey,
                    userId: credentialStore.userId
                )
                credentialStore.userSecret = registration.userSecret
            }

            guard let credentials = credentialStore.snapshot else {
                lastError = "Missing SnapTrade credentials."
                return
            }

            let login = try await apiClient.generateLoginURL(credentials: credentials, customRedirect: "ledger://snaptrade-callback")
            guard let portalURL = URL(string: login.redirectURI) else {
                lastError = "SnapTrade returned an invalid connection URL."
                return
            }

            _ = try await connectSession.connect(portalURL: portalURL)
            refreshState()
            await sync()
        } catch SnapTradeConnectSession.ConnectError.cancelled {
            // User backed out of the connection portal; nothing to surface as an error.
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
            let source = SnapTradeTransactionSource(credentials: credentials, client: apiClient)
            let importService = TransactionImportService(modelContext: modelContext)
            lastSyncSummary = try await importService.importAll(from: source, sourceKind: .snapTrade)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func disconnect() {
        credentialStore.disconnect()
        refreshState()
    }
}
