import SwiftUI

/// Bloom empty state — warm illustration, short headline, and a single primary action. No tutorial
/// copy; the app is for a single user, so empty surfaces stay minimal and direct.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [Palette.green.opacity(0.16), Color.clear]),
                            center: .center,
                            startRadius: 10,
                            endRadius: 70
                        )
                    )
                    .frame(width: 130, height: 130)

                Image(systemName: systemImage)
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(Palette.greenDeep)
            }

            Text(title)
                .font(.appTitle3.weight(.heavy))
                .multilineTextAlignment(.center)

            Text(message)
                .font(.appSubheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 30)

            if let actionTitle, let action {
                AccentButton(title: actionTitle, systemName: systemImage, accent: .dashboard, action: action)
                    .padding(.top, 6)
                    .padding(.horizontal, 40)
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    EmptyStateView(
        systemImage: "banknote",
        title: "No Accounts Yet",
        message: "Add a chequing, savings, credit, or investment account to get started.",
        actionTitle: "Add Account",
        action: {}
    )
}
