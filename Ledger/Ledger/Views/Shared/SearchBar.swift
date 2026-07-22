import SwiftUI

/// The app's standard search field: a rounded, capsule-shaped pill (magnifying glass, text field,
/// and a trailing mic/clear glyph) paired with a separate circular cancel button — the system
/// search-bar shape. Every search menu uses this so they all look and animate the same way; present
/// it with `View.searchBarRow(...)` to get the standard unfurl-from-the-button transition for free.
struct SearchBar: View {
    @Binding var text: String
    var placeholder: String = "Search"
    /// The parent owns the focus state and passes it in, so it can raise/drop the keyboard as the
    /// bar expands and collapses.
    @FocusState.Binding var isFocused: Bool
    /// Tapped when the circular cancel button is pressed — the parent collapses the bar and clears.
    var onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            field
            cancelButton
        }
        // Swap the trailing mic/clear glyph with a clean spring rather than a hard cut.
        .animation(.snappy(duration: 0.2), value: text.isEmpty)
    }

    /// The pill itself: leading magnifying glass, the text field, and a trailing accessory.
    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            trailingAccessory
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.appSurface, in: Capsule(style: .continuous))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06)))
    }

    /// A mic glyph while the field is empty (matching the system search look), swapping to an inline
    /// clear button once there's text to remove.
    @ViewBuilder
    private var trailingAccessory: some View {
        if text.isEmpty {
            Image(systemName: "mic.fill")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
                .transition(.scale.combined(with: .opacity))
        } else {
            Button {
                text = ""
                isFocused = true
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear search")
            .transition(.scale.combined(with: .opacity))
        }
    }

    /// The standalone circular cancel button that dismisses the search field.
    private var cancelButton: some View {
        Button(action: onCancel) {
            Image(systemName: "xmark")
                .font(AppFont.scaled(15, relativeTo: .subheadline, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
                .background(Color.appSurface, in: Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cancel search")
    }
}

extension View {
    /// Reveals a `SearchBar` above `self` when `isPresented` is true. Rather than dropping in as a
    /// full-width block, the bar unrolls straight sideways from its trailing edge — right under the
    /// toolbar's search button — so it reads as stretching *out of the button itself* and rolling back
    /// into it. Every search menu opens and closes identically off this one helper.
    func searchBarRow(
        isPresented: Bool,
        text: Binding<String>,
        placeholder: String = "Search",
        isFocused: FocusState<Bool>.Binding,
        onCancel: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            if isPresented {
                SearchBar(
                    text: text,
                    placeholder: placeholder,
                    isFocused: isFocused,
                    onCancel: onCancel
                )
                .padding(.horizontal)
                .padding(.top, 4)
                .padding(.bottom, 8)
                // Unroll straight out of the trailing edge (under the search button) — widening
                // leftward at full height — so the bar looks like it grows out of the button itself
                // and rolls back into it on cancel.
                .transition(.searchExpand)
            }
            self
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: isPresented)
    }
}

/// Drives the search bar's open/close as a purely sideways unroll: the trailing edge (where the
/// button sits) stays pinned and full-height while the bar stretches out to the left, so it reads as
/// the button *expanding out into itself* — and rolls back into the button on cancel. Width only, no
/// vertical grow, so it never looks like a block dropping in.
private struct SearchExpandModifier: ViewModifier, Animatable {
    /// 0 = collapsed to a button-width nub at the trailing edge, 1 = fully unrolled.
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            // Horizontal only, pinned at the right edge: the bar starts about a button-width wide and
            // unrolls leftward to full width, keeping its full height the whole time.
            .scaleEffect(
                x: 0.12 + 0.88 * progress,
                y: 1,
                anchor: .trailing
            )
            .opacity(progress)
    }
}

extension AnyTransition {
    /// Grows the search bar out of the toolbar's search button by unrolling it sideways from the
    /// trailing edge, instead of appearing as a block underneath it.
    static var searchExpand: AnyTransition {
        .modifier(active: SearchExpandModifier(progress: 0), identity: SearchExpandModifier(progress: 1))
    }
}

#Preview {
    struct PreviewHost: View {
        @State private var text = ""
        @FocusState private var focused: Bool
        var body: some View {
            Color(.systemBackground)
                .ignoresSafeArea()
                .searchBarRow(
                    isPresented: true,
                    text: $text,
                    placeholder: "Search merchants",
                    isFocused: $focused,
                    onCancel: {}
                )
        }
    }
    return PreviewHost()
}
