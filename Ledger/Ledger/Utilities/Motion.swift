import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Shared motion vocabulary for the redesign — one set of springs used everywhere so every expand,
/// tap, and transition feels like the same lively hand. Deliberately a little under-damped for the
/// playful overshoot the redesign is going for.
nonisolated enum Motion {
    /// The signature bouncy spring — a clear overshoot for taps, expands, appears, and selection.
    static let bouncy = Animation.spring(response: 0.42, dampingFraction: 0.6)
    /// A snappier spring for small state flips (chevrons, badges, toggles).
    static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.7)
    /// A smooth, well-damped spring for larger layout changes where overshoot would feel busy.
    static let smooth = Animation.spring(response: 0.5, dampingFraction: 0.86)
    /// A gentle ease for count-up numbers.
    static let count = Animation.easeOut(duration: 0.8)
}

/// Gives every tappable surface the same lively feedback: it dips and softens on press, then springs
/// back with an overshoot, with a light haptic on touch-down. Apply with `.buttonStyle(.pressable)`
/// on Buttons and NavigationLinks so the whole app answers touch identically.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.95
    var haptics: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(Motion.bouncy, value: configuration.isPressed)
            .sensoryFeedback(trigger: configuration.isPressed) { _, pressed in
                haptics && pressed ? .impact(weight: .light, intensity: 0.5) : nil
            }
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    /// The app's standard springy, haptic button feel.
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
    static func pressable(scale: CGFloat = 0.95, haptics: Bool = true) -> PressableButtonStyle {
        PressableButtonStyle(scale: scale, haptics: haptics)
    }
}

/// A springy entrance: content pops in from slightly small and transparent the first time it appears.
/// Best on a handful of hero elements — not long lists, where cell recycling would re-trigger it.
private struct BouncyAppear: ViewModifier {
    let delay: Double
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown ? 1 : 0.92)
            .opacity(shown ? 1 : 0)
            .onAppear {
                withAnimation(Motion.bouncy.delay(delay)) { shown = true }
            }
    }
}

extension View {
    /// Pop this view in with the signature spring when it first appears.
    func bouncyAppear(delay: Double = 0) -> some View { modifier(BouncyAppear(delay: delay)) }
}

/// Small wrappers over UIKit's haptic generators for the moments a `.pressable` button style can't
/// cover (a value committed, a swipe action, a successful save). Keeps the call sites one-liners.
enum Haptics {
    @MainActor static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    @MainActor static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    @MainActor static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
