import Foundation
import SwiftData

@Model
final class Tag {
    var name: String
    var colorHex: String
    var createdAt: Date

    init(name: String, colorHex: String = "#8E8E93") {
        self.name = name
        self.colorHex = colorHex
        self.createdAt = .now
    }
}
