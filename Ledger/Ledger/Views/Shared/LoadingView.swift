import SwiftUI

/// Bloom loading state — a shimmer-skeleton card layout instead of a bare spinner, so even the wait
/// feels like the rest of the app.
struct LoadingView: View {
    var message: String = "Loading…"
    @State private var phase: CGFloat = -1

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                heroSkeleton
                HStack(spacing: Theme.sectionSpacing) {
                    statSkeleton
                    statSkeleton
                    statSkeleton
                }
                listSkeleton
                listSkeleton
            }
            .padding()
        }
        .background(Color.appBackground.ignoresSafeArea())
        .overlay(alignment: .top) {
            HStack(spacing: 6) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Palette.greenDeep)
                Text(message)
                    .font(.appCaption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 18)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }

    private var shimmer: some View {
        GeometryReader { geo in
            LinearGradient(
                gradient: Gradient(colors: [Color.appSurface, Color.appSurface.opacity(0.5), Color.appSurface]),
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: geo.size.width * 2)
            .offset(x: phase * geo.size.width)
        }
    }

    private var heroSkeleton: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(Color.appSurface)
                .frame(width: 104, height: 104)
                .overlay(shimmer)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.appSurface)
                    .frame(width: 120, height: 12)
                    .overlay(shimmer)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.appSurface)
                    .frame(width: 180, height: 30)
                    .overlay(shimmer)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.appSurface)
                    .frame(width: 100, height: 14)
                    .overlay(shimmer)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.cardPadding)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private var statSkeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.appSurface)
                .frame(height: 10)
                .overlay(shimmer)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.appSurface)
                .frame(height: 20)
                .overlay(shimmer)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private var listSkeleton: some View {
        VStack(alignment: .leading, spacing: 18) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.appSurface)
                .frame(width: 140, height: 14)
                .overlay(shimmer)
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(Color.appSurface)
                .frame(height: 15)
                .overlay(shimmer)
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(Color.appSurface)
                .frame(width: 180, height: 15)
                .overlay(shimmer)
        }
        .padding(Theme.cardPadding)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

#Preview {
    LoadingView()
}
