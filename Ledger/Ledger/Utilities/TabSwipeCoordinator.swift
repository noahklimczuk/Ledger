import Observation
import SwiftUI

/// Tracks whether any tab's navigation stack currently has a pushed (non-root) screen. While one
/// does, `RootTabView` disables the paged tab swipe, so a horizontal swipe acts as "go back"
/// (the system interactive pop) instead of yanking the user to the neighbouring tab. On root
/// screens the tab swipe works as before.
@MainActor
@Observable
final class TabSwipeCoordinator {
    private(set) var pushedScreenCount = 0

    var isTabSwipeEnabled: Bool { pushedScreenCount == 0 }

    func screenAppeared() { pushedScreenCount += 1 }

    func screenDisappeared() { pushedScreenCount = max(0, pushedScreenCount - 1) }
}

/// Apply to every screen that gets *pushed* inside a tab (not sheets — they already block the
/// tab swipe by covering it). Counts the screen in/out of `TabSwipeCoordinator` as it appears
/// and disappears; the counter handles stacked pushes, where a deeper push hides the screen
/// below before revealing its own.
private struct DisablesTabSwipe: ViewModifier {
    @Environment(TabSwipeCoordinator.self) private var coordinator: TabSwipeCoordinator?

    func body(content: Content) -> some View {
        content
            .onAppear { coordinator?.screenAppeared() }
            .onDisappear { coordinator?.screenDisappeared() }
    }
}

extension View {
    /// Marks this view as a pushed screen: while it's on screen, the root tab swipe is disabled
    /// so swiping goes back instead of changing tabs.
    func disablesTabSwipe() -> some View {
        modifier(DisablesTabSwipe())
    }
}
