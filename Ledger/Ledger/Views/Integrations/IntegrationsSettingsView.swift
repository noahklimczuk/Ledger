import SwiftUI
import SwiftData

/// Bloom-styled Wealthsimple connection sheet. Direct login, no aggregator. Your credentials go
/// only to Wealthsimple; Ledger stores the resulting session token in the iOS Keychain.
struct IntegrationsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: IntegrationsViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    ScrollView {
                        VStack(spacing: Theme.sectionSpacing) {
                            statusCard(viewModel)
                            if viewModel.connectionState == .notConnected {
                                signInCard(viewModel)
                            }
                            if viewModel.connectionState == .connected {
                                connectedActions(viewModel)
                            }
                            if let summary = viewModel.lastSyncSummary {
                                syncSummaryCard(summary)
                            }
                            if let lastError = viewModel.lastError {
                                errorBanner(lastError)
                            }
                        }
                        .padding()
                    }
                    .background(Color.appBackground.ignoresSafeArea())
                } else {
                    LoadingView()
                }
            }
            .navigationTitle("Connect Wealthsimple")
            .navigationBarTitleDisplayMode(.inline)
            .accent(.accounts)
            .accentWash(.accounts)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task {
            if viewModel == nil { viewModel = IntegrationsViewModel(modelContext: modelContext) }
        }
    }

    // MARK: - Status

    private func statusCard(_ viewModel: IntegrationsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                IconBadge(systemName: "link", accent: .accounts, size: 46, filled: false)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Wealthsimple")
                        .font(.appHeadline.weight(.heavy))
                    Text(viewModel.connectionState == .connected ? "Connected" : "Not connected")
                        .font(.appSubheadline)
                        .foregroundStyle(viewModel.connectionState == .connected ? Palette.income : Palette.amber)
                }
                Spacer()
            }

            Text("Ledger signs in directly with your Wealthsimple login. Your password is sent only to Wealthsimple; Ledger stores just the secure session token in your Keychain.")
                .font(.appFootnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.cardPadding)
        .card()
    }

    // MARK: - Sign in

    private func signInCard(_ viewModel: IntegrationsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sign in")
                .font(.appCaption2.weight(.heavy))
                .tracking(0.4)
                .foregroundStyle(.secondary)

            TextField("Email", text: Binding(get: { viewModel.email }, set: { viewModel.email = $0 }))
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(14)
                .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Color.appHairline, lineWidth: 1))

            SecureField("Password", text: Binding(get: { viewModel.password }, set: { viewModel.password = $0 }))
                .textContentType(.password)
                .padding(14)
                .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Color.appHairline, lineWidth: 1))

            if viewModel.needsOTP {
                TextField("2-step code", text: Binding(get: { viewModel.otp }, set: { viewModel.otp = $0 }))
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .padding(14)
                    .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Color.appHairline, lineWidth: 1))
            }

            Button {
                Task { await viewModel.connect() }
            } label: {
                HStack {
                    if viewModel.isBusy {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Text(viewModel.needsOTP ? "Verify & Connect" : "Connect Wealthsimple")
                    }
                }
                .font(.appSubheadline.weight(.black))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isBusy || viewModel.email.isEmpty || viewModel.password.isEmpty)
        }
        .padding(Theme.cardPadding)
        .card()
    }

    // MARK: - Connected actions

    private func connectedActions(_ viewModel: IntegrationsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.needsReauth {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Palette.amber)
                    Text("Wealthsimple needs you to sign in again to keep syncing.")
                        .font(.appSubheadline.weight(.semibold))
                        .foregroundStyle(Palette.amberDeep)
                }
                .padding(14)
                .background(Palette.amber.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            }

            if viewModel.connectionState == .connected {
                HStack {
                    Text("Last synced")
                        .font(.appBodyMedium.weight(.semibold))
                    Spacer()
                    Text(viewModel.lastSyncedAt.map { $0.formatted(.relative(presentation: .named)) } ?? "Never")
                        .font(.appBody)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await viewModel.sync() }
                } label: {
                    Label("Sync Now", systemImage: "arrow.clockwise")
                        .font(.appSubheadline.weight(.black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isBusy)

                Button {
                    viewModel.disconnect()
                } label: {
                    Label("Disconnect", systemImage: "link.icloud.slash")
                        .font(.appSubheadline.weight(.black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(Palette.coral)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Theme.cardPadding)
        .card()
    }

    // MARK: - Summary / error

    private func syncSummaryCard(_ summary: IntegrationsViewModel.LastSyncSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last Sync")
                .font(.appCaption2.weight(.heavy))
                .tracking(0.4)
                .foregroundStyle(.secondary)
            Text("\(summary.accountsCreated) accounts added, \(summary.transactionsCreated) new transactions, \(summary.transactionsSkipped) already up to date.")
                .font(.appSubheadline)
                .foregroundStyle(.secondary)
        }
        .padding(Theme.cardPadding)
        .card()
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.coral)
            Text(message)
                .font(.appSubheadline.weight(.semibold))
                .foregroundStyle(Palette.coralDeep)
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.coral.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Palette.coral.opacity(0.18), lineWidth: 1))
    }
}

#Preview {
    NavigationStack {
        IntegrationsSettingsView()
    }
    .modelContainer(for: LedgerSchema.models, inMemory: true)
}
