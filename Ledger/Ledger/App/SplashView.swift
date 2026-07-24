import SwiftUI

/// Branded launch/loading screen shown on cold start, over the periwinkle→peach wash so it blends
/// out of the native launch screen (`UILaunchScreen` uses the matching `LaunchBackground` color). The
/// app logo and wordmark animate in and a loading indicator spins underneath while the first data
/// refresh runs; `LedgerApp` fades the whole thing away once startup settles.
struct SplashView: View {
    @State private var appeared = false

    var body: some View {
        ZStack {
            LinearGradient.brand
                .ignoresSafeArea()

            VStack(spacing: 22) {
                // The real app logo, presented as a rounded app-icon tile so it reads as the brand
                // mark rather than a flat glyph. A soft ring + shadow lift it off the gradient.
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 132, height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.25), radius: 18, y: 10)
                    .scaleEffect(appeared ? 1 : 0.7)
                    .opacity(appeared ? 1 : 0)

                Text("Ledger")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .opacity(appeared ? 1 : 0)

                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .padding(.top, 4)
                    .opacity(appeared ? 0.9 : 0)
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
