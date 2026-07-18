import SwiftUI

extension Color {
    // nonisolated so the design-system palette (which the project defaults to @MainActor) can build
    // its shared colors as nonisolated statics. Pure math over a string — safe off the main actor.
    nonisolated init(hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized.removeAll { $0 == "#" }

        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)

        let r: UInt64
        let g: UInt64
        let b: UInt64
        if sanitized.count == 6 {
            r = (value >> 16) & 0xFF
            g = (value >> 8) & 0xFF
            b = value & 0xFF
        } else {
            r = 142
            g = 142
            b = 147
        }

        self.init(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}
