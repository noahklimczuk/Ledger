import SwiftUI
import SwiftData

/// The only screen for Plaid setup + Wealthsimple *bank-account* connection. There's no separate
/// "ConnectWealthsimpleView" -- the actual connect flow is driven by ASWebAuthenticationSession
/// (see PlaidConnectSession), which presents Plaid's own hosted UI, so a Connect button here
/// is the entire surface needed.
struct IntegrationsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: IntegrationsViewModel?

    var body: some View {
        Group {
            if let viewModel {
                Form {
                    Section {
                        Text("Ledger uses Plaid, a licensed third-party account aggregator, to securely connect your Wealthsimple bank accounts (Wealthsimple Cash, chequing and savings). Your Wealthsimple credentials are entered on Plaid's hosted login page and never touch this app.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Section("Plaid API Credentials") {
                        TextField("Client ID", text: Binding(get: { viewModel.clientId }, set: { viewModel.clientId = $0 }))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Secret", text: Binding(get: { viewModel.secret }, set: { viewModel.secret = $0 }))
                        Picker("Environment", selection: Binding(get: { viewModel.environment }, set: { viewModel.environment = $0 })) {
                            ForEach(PlaidEnvironment.allCases) { env in
                                Text(env.displayName).tag(env)
                            }
                        }
                        Button("Save Credentials") {
                            viewModel.saveAPICredentials()
                        }
                        .disabled(viewModel.clientId.isEmpty || viewModel.secret.isEmpty)

                        Link("Get API keys at dashboard.plaid.com", destination: URL(string: "https://dashboard.plaid.com")!)
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
