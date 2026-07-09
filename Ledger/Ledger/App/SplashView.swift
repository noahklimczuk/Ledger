import SwiftUI

/// Branded launch/loading screen shown briefly on cold start, over the emerald→teal wash so it
/// blends out of the native launch screen (`UILaunchScreen` uses the matching `LaunchBackground`
/// color). The mark animates in, then `LedgerApp` fades the whole thing away.
struct SplashView: View {
    @State private var appeared = false

    var body: some View {
        ZStack {
            LinearGradient.brand
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 76, weight: .bold))
                    .foregroundStyle(.white)
                    .scaleEffect(appeared ? 1 : 0.7)
                    .opacity(appeared ? 1 : 0)

                Text("Ledger")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .opacity(appeared ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.72)) {
                appeared = true
            }
        }
    }
}

#Preview {
    SplashView()
}
