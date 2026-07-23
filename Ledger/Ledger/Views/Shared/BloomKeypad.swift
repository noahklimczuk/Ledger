import SwiftUI

/// A custom, Bloom-styled number pad for entering transaction amounts. It edits a plain text string
/// (currency formatting is applied by the caller) and limits input to one decimal separator.
struct BloomKeypad: View {
    @Binding var value: String

    private let rows: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        [".", "0", "⌫"]
    ]

    var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(rows, id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { key in
                        KeyButton(key: key) { tap(key) }
                            .gridCellColumns(key == "0" ? 2 : 1)
                    }
                }
            }
        }
    }

    private func tap(_ key: String) {
        Haptics.tap(.soft)
        switch key {
        case "⌫":
            if !value.isEmpty { value.removeLast() }
        case ".":
            if !value.contains(".") { value.append(".") }
        default:
            if value == "0" { value = key } else { value.append(key) }
        }
    }
}

private struct KeyButton: View {
    let key: String
    let action: () -> Void

    private var isMut: Bool { key == "." || key == "⌫" }

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.appSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(stops: [
                                        .init(color: Color.white.opacity(0.18), location: 0),
                                        .init(color: Color.clear, location: 0.3),
                                        .init(color: Color.clear, location: 0.7),
                                        .init(color: Color.black.opacity(0.06), location: 1)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .blendMode(.overlay)
                    )
                    .shadow(color: Color.bloomShadow, radius: 4, x: 2, y: 3)
                    .shadow(color: Color.bloomHighlight, radius: 3, x: -1, y: -1)

                Text(key)
                    .font(AppFont.scaled(isMut ? 20 : 22, relativeTo: .headline, weight: isMut ? .bold : .heavy))
                    .foregroundStyle(isMut ? Color.secondary : Color.primary)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    @Previewable @State var value = ""
    BloomKeypad(value: $value)
}
