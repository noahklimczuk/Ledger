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
        VStack(spacing: 10) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(row, id: \.self) { key in
                        KeyButton(key: key) { tap(key) }
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

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.appSurface)
                    .shadow(color: Color.bloomShadow, radius: 4, x: 2, y: 3)
                    .shadow(color: Color.bloomHighlight, radius: 3, x: -1, y: -1)

                Text(key)
                    .font(key == "⌫" ? .system(size: 22, weight: .bold) : .system(size: 24, weight: .heavy))
                    .foregroundStyle(Color.primary)
            }
            .aspectRatio(1.45, contentMode: .fit)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    @Previewable @State var value = ""
    BloomKeypad(value: $value)
}
