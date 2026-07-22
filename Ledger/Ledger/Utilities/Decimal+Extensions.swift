import Foundation

extension Decimal {
    /// A magnitude that doesn't rely on `Decimal` conforming to `SignedNumeric` in every SDK slice.
    nonisolated var absoluteValue: Decimal {
        self.sign == .minus ? Decimal(0) - self : self
    }
}

nonisolated func abs(_ value: Decimal) -> Decimal { value.absoluteValue }

