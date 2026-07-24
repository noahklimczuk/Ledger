import SwiftUI

/// Bloom error state — a warm banner with the problem, an explanation, and a retry action.
struct ErrorStateView: View {
    let message: String
    var retryTitle: String = "Try Again"
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Palette.coral.opacity(0.12))
                    .frame(width: 110, height: 110)

                Text("⚠️")
                    .font(.system(size: 44))
                    .foregroundStyle(Palette.coral)
            }

            Text("Something went wrong")
                .font(.appTitle3.weight(.heavy))

            Text(message)
                .font(.appSubheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 30)

            if let retry {
                AccentButton(title: retryTitle, systemName: "arrow.clockwise", accent: .debt, action: retry)
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
    ErrorStateView(message: "Couldn't load your accounts.", retry: {})
}
