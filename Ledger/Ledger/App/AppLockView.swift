import SwiftUI

struct AppLockView: View {
    var lockService: AppLockService

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("Ledger is Locked")
                .font(.title2.bold())

            if case .unavailable(let message) = lockService.state {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button {
                Task { await lockService.authenticate() }
            } label: {
                Label("Unlock", systemImage: "faceid")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .task {
            await lockService.authenticate()
        }
    }
}

#Preview {
    AppLockView(lockService: AppLockService())
}
