import SwiftUI
import SwiftData

/// The screen for connecting a Wealthsimple **Cash** account directly, using the user's own
/// Wealthsimple login. There's no aggregator and no API keys -- just email/password and, when
/// prompted, a 2-step verification code. The resulting session is stored in the Keychain and used
/// to sync accounts + activity (`IntegrationsViewModel` → `WealthsimpleSyncCoordinator`).
struct IntegrationsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: IntegrationsViewModel?

    var body: some View {
        Group {
            if let viewModel {
                Form {
                    Section {
                        Text("Ledger connects directly to Wealthsimple with your own login to pull in your Wealthsimple Cash account and its transactions. Your email and password are sent only to Wealthsimple to sign in — Ledger keeps just the resulting secure token, in the iOS Keychain.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if viewModel.connectionState == .notConnected {
                        signInSection(viewModel)
                    }

                    Section("Wealthsimple") {
                        statusRow(viewModel)

                        if viewModel.connectionState == .connected {
                            lastSyncedRow(viewModel)
                        }

                        if viewModel.needsReauth {
                            Label("Wealthsimple needs you to sign in again to keep syncing.", systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(.orange)
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

                    if viewModel.connectionState == .connected {
                        Section {
                            Text("Ledger syncs automatically when you open the app (at most every few hours). Your manual edits are always kept — a re-sync never overwrites a transaction or account you've changed.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
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

    @ViewBuilder
    private func signInSection(_ viewModel: IntegrationsViewModel) -> some View {
        Section("Sign in to Wealthsimple") {
            TextField("Email", text: Binding(get: { viewModel.email }, set: { viewModel.email = $0 }))
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Password", text: Binding(get: { viewModel.password }, set: { viewModel.password = $0 }))
                .textContentType(.password)

            if viewModel.needsOTP {
                TextField("2-step verification code", text: Binding(get: { viewModel.otp }, set: { viewModel.otp = $0 }))
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
            }

            Button {
                Task { await viewModel.connect() }
            } label: {
                if viewModel.isBusy {
                    ProgressView()
                } else {
                    Text(viewModel.needsOTP ? "Verify & Connect" : "Connect Wealthsimple")
                }
            }
            .disabled(viewModel.isBusy || viewModel.email.isEmpty || viewModel.password.isEmpty)
        }
    }

    private func statusRow(_ viewModel: IntegrationsViewModel) -> some View {
        HStack {
            Text("Status")
            Spacer()
            switch viewModel.connectionState {
            case .notConnected:
                Label("Not Connected", systemImage: "circle").foregroundStyle(.orange)
            case .connected:
                Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
    }

    private func lastSyncedRow(_ viewModel: IntegrationsViewModel) -> some View {
        HStack {
            Text("Last Synced")
            Spacer()
            Text(viewModel.lastSyncedAt.map { $0.formatted(.relative(presentation: .named)) } ?? "Never")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        IntegrationsSettingsView()
    }
    .modelContainer(for: LedgerSchema.models, inMemory: true)
}
