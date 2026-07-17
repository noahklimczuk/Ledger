import SwiftUI

/// The app's standard search field: a rounded, capsule-shaped pill (magnifying glass, text field,
/// and a trailing mic/clear glyph) paired with a separate circular cancel button — the system
/// search-bar shape. Every search menu uses this so they all look and animate the same way; present
/// it with `View.searchBarRow(...)` to get the standard slide-in/out transition for free.
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
        .background(.thinMaterial, in: Capsule())
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
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
                .background(.thinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cancel search")
    }
}

extension View {
    /// Slides a `SearchBar` in above `self` when `isPresented` is true, using the app's standard
    /// search transition and spring so every search menu opens and closes identically. The bar and
    /// the content below it move together as one clean unit.
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
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            self
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: isPresented)
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
