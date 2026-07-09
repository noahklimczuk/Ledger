import Foundation

/// Estimates how long a debt takes to clear given a fixed monthly payment, using standard
/// amortization. Returns nil when the payment can't cover the monthly interest (the balance never
/// falls), so callers can surface a "payment too low" state instead of an infinite timeline.
enum DebtPayoffCalculator {
    struct Projection {
        let months: Int
        let totalInterest: Decimal
    }

    static func project(balance: Decimal, annualInterestRate: Double, monthlyPayment: Decimal) -> Projection? {
        let principal = (balance as NSDecimalNumber).doubleValue
        let payment = (monthlyPayment as NSDecimalNumber).doubleValue
        guard principal > 0 else { return Projection(months: 0, totalInterest: 0) }
        guard payment > 0 else { return nil }

        let monthlyRate = annualInterestRate / 100.0 / 12.0

        // No interest: straight division.
        if monthlyRate <= 0 {
            let months = Int((principal / payment).rounded(.up))
            let totalPaid = payment * Double(months)
            return Projection(months: months, totalInterest: decimal(max(totalPaid - principal, 0)))
        }

        // Payment doesn't even cover the first month's interest — balance grows forever.
        if payment <= principal * monthlyRate {
            return nil
        }

        let months = -log(1 - (principal * monthlyRate) / payment) / log(1 + monthlyRate)
        let roundedMonths = Int(months.rounded(.up))
        let totalPaid = payment * Double(roundedMonths)
        return Projection(months: roundedMonths, totalInterest: decimal(max(totalPaid - principal, 0)))
    }

    /// A human-readable duration like "1 yr 4 mo" or "8 mo".
    static func durationText(months: Int) -> String {
        guard months > 0 else { return "Paid off" }
        let years = months / 12
        let remaining = months % 12
        switch (years, remaining) {
        case (0, _): return "\(remaining) mo"
        case (_, 0): return "\(years) yr"
        default: return "\(years) yr \(remaining) mo"
        }
    }

    private static func decimal(_ value: Double) -> Decimal {
        Decimal(value).rounded(2)
    }
}

private extension Decimal {
    func rounded(_ scale: Int) -> Decimal {
        var input = self
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, .plain)
        return result
    }
}
