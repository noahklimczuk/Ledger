import SwiftUI

struct IconPickerView: View {
    @Binding var selection: String

    private let symbols = [
        "cart.fill", "fork.knife", "car.fill", "house.fill", "bolt.fill",
        "bag.fill", "gift.fill", "airplane", "tram.fill", "fuelpump.fill",
        "cross.case.fill", "pills.fill", "gamecontroller.fill", "film.fill",
        "book.fill", "graduationcap.fill", "pawprint.fill", "wifi",
        "phone.fill", "creditcard.fill", "banknote.fill", "briefcase.fill",
        "wrench.and.screwdriver.fill", "paintbrush.fill", "cup.and.saucer.fill",
        "tshirt.fill", "figure.walk", "heart.fill", "star.fill", "tag.fill"
    ]

    private let columns = Array(repeating: GridItem(.flexible()), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(symbols, id: \.self) { symbol in
                Button {
                    selection = symbol
                } label: {
                    Image(systemName: symbol)
                        .font(.title3)
                        .frame(width: 40, height: 40)
                        .background(selection == symbol ? Color.accentColor.opacity(0.2) : Color.clear, in: Circle())
                }
            }
        }
    }
}

struct ColorPickerGridView: View {
    @Binding var selectionHex: String

    private let hexColors = [
        "#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#00C7BE",
        "#30B0C7", "#32ADE6", "#007AFF", "#5856D6", "#AF52DE",
        "#FF2D55", "#A2845E", "#8E8E93"
    ]

    private let columns = Array(repeating: GridItem(.flexible()), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(hexColors, id: \.self) { hex in
                Button {
                    selectionHex = hex
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 32, height: 32)
                        .overlay {
                            if selectionHex == hex {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.white)
                                    .font(.caption.bold())
                            }
                        }
                }
            }
        }
    }
}
