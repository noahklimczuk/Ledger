import SwiftUI
import SwiftData

/// The only screen for SnapTrade setup + Wealthsimple connection. There's no separate
/// "ConnectWealthsimpleView" -- the actual connect flow is driven by ASWebAuthenticationSession
/// (see SnapTradeConnectSession), which presents its own system UI, so a Connect button here
/// is the entire surface needed.
struct IntegrationsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: IntegrationsViewModel?

    var body: some View {
        Group {
            if let viewModel {
                Form {
                    Section {
                        Text("Ledger uses SnapTrade, a licensed third-party account aggregator, to securely connect your Wealthsimple accounts. Your Wealthsimple credentials are entered on SnapTrade's hosted login page and never touch this app.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Section("SnapTrade API Credentials") {
                        TextField("Client ID", text: Binding(get: { viewModel.clientId }, set: { viewModel.clientId = $0 }))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Consumer Key", text: Binding(get: { viewModel.consumerKey }, set: { viewModel.consumerKey = $0 }))
                        Button("Save Credentials") {
                            viewModel.saveAPICredentials()
                        }
                        .disabled(viewModel.clientId.isEmpty || viewModel.consumerKey.isEmpty)

                        Link("Get API keys at snaptrade.com", destination: URL(string: "https://snaptrade.com")!)
                            .font(.footnote)
                    }

                    Section("Wealthsimple") {
                        statusRow(viewModel)

                        if viewModel.connectionState != .notConfigured {
                            Button {
                                Task { await viewModel.connectWealthsimple() }
                            } label: {
                                if viewModel.isBusy {
                                    ProgressView()
                                } else {
                                    Text(viewModel.connectionState == .connected ? "Reconnect" : "Connect Wealthsimple")
                                }
                            }
                            .disabled(viewModel.isBusy)
                        }

                        if viewModel.connectionState == .connected {
                            Button("Sync Now") {
                                Task { await viewModel.sync() }
                            }
                            .disabled(viewModel.isBusy)

                            Button("Disconnect", role: .destructive) {
                                viewModel.disconnect()
                            }
                        }
                    }

                    if let summary = viewModel.lastSyncSummary {
                        Section("Last Sync") {
                            Text("\(summary.accountsCreated) accounts added, \(summary.transactionsCreated) new transactions, \(summary.transactionsSkipped) already up to date.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let lastError = viewModel.lastError {
                        Section {
                            Text(lastError)
                                .foregroundStyle(.red)
                                .font(.footnote)
                        }
                    }
                }
            } else {
                LoadingView()
            }
        }
        .navigationTitle("Connect Wealthsimple")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if viewModel == nil { viewModel = IntegrationsViewModel(modelContext: modelContext) }
        }
    }

    private func statusRow(_ viewModel: IntegrationsViewModel) -> some View {
        HStack {
            Text("Status")
            Spacer()
            switch viewModel.connectionState {
            case .notConfigured:
                Label("Not Configured", systemImage: "xmark.circle").foregroundStyle(.secondary)
            case .configuredNotConnected:
                Label("Not Connected", systemImage: "circle").foregroundStyle(.orange)
            case .connected:
                Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
    }
}

#Preview {
    NavigationStack {
        IntegrationsSettingsView()
    }
    .modelContainer(for: LedgerSchema.models, inMemory: true)
}
