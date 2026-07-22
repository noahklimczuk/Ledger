import SwiftUI

/// The Bloom Face ID lock screen. Appears over the app when the user leaves and returns, keeping
/// the private financial data on-device. Uses the real Ledger app logo and a soft green halo around
/// the Face ID glyph, with a passcode fallback.
struct AppLockView: View {
    var lockService: AppLockService
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 22) {
                    Image("LaunchLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.12), radius: 18, y: 10)
                        .scaleEffect(appeared ? 1 : 0.8)
                        .opacity(appeared ? 1 : 0)

                    VStack(spacing: 10) {
                        Text("Ledger is locked")
                            .font(.appTitle.weight(.heavy))
                            .foregroundStyle(Color.primary)

                        Text("Your money is private and stays on this iPhone.")
                            .font(.appSubheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()

                VStack(spacing: 24) {
                    Button {
                        Task { await lockService.authenticate() }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        gradient: Gradient(colors: [Palette.green.opacity(0.22), Color.clear]),
                                        center: .center,
                                        startRadius: 20,
                                        endRadius: 75
                                    )
                                )
                                .frame(width: 150, height: 150)

                            Image(systemName: "faceid")
                                .font(.system(size: 64, weight: .regular))
                                .foregroundStyle(Palette.greenDeep)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Unlock with Face ID")

                    Text("Look to unlock")
                        .font(.appSubheadline.weight(.heavy))
                        .foregroundStyle(Palette.greenDeep)

                    if case .unavailable(let message) = lockService.state {
                        Text(message)
                            .font(.appCaption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }

                    Button {
                        Task { await lockService.authenticateWithPasscode() }
                    } label: {
                        Text("Use passcode instead")
                            .font(.appSubheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }

                Spacer()
            }
            .padding(.horizontal, 40)
        }
        .task {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.72)) {
                appeared = true
            }
            await lockService.authenticate()
        }
    }
}

#Preview {
    AppLockView(lockService: AppLockService())
}
