import SwiftUI

struct LoadingView: View {
    var message: String = "Loading…"
    @State private var animating = false

    var body: some View {
        VStack(spacing: 16) {
            // A gently pulsing brand mark instead of a bare spinner, so even the loading state
            // carries the redesign's playful character.
            Circle()
                .fill(LinearGradient.brand)
                .frame(width: 46, height: 46)
                .scaleEffect(animating ? 1 : 0.66)
                .opacity(animating ? 1 : 0.55)
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: animating)
                .onAppear { animating = true }
            Text(message)
                .font(.appFootnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    LoadingView()
}
