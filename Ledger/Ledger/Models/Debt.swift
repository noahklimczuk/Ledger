import Foundation
import SwiftData

enum DebtKind: String, Codable, CaseIterable, Identifiable {
    case creditCard
    case lineOfCredit
    case studentLoan
    case carLoan
    case mortgage
    case personalLoan
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .creditCard: "Credit Card"
        case .lineOfCredit: "Line of Credit"
        case .studentLoan: "Student Loan"
        case .carLoan: "Car Loan"
        case .mortgage: "Mortgage"
        case .personalLoan: "Personal Loan"
        case .other: "Other"
        }
    }

    var sfSymbolName: String {
        switch self {
        case .creditCard: "creditcard.fill"
        case .lineOfCredit: "arrow.left.arrow.right.circle.fill"
        case .studentLoan: "graduationcap.fill"
        case .carLoan: "car.fill"
        case .mortgage: "house.fill"
        case .personalLoan: "person.fill"
        case .other: "banknote.fill"
        }
    }
}

/// A debt the user is paying down. Tracked separately from `Account` (which models an asset or a
/// live credit-card balance): a `Debt` is a manually-maintained obligation with an interest rate
/// and a minimum payment, used to estimate a payoff timeline.
@Model
final class Debt {
    var name: String
    var kind: DebtKind
    /// Amount still owed, stored as a positive number.
    var currentBalance: Decimal
    /// Annual interest rate as a percentage, e.g. 19.99 for a 19.99% APR card.
    var annualInterestRate: Double
    /// The regular monthly payment the user makes (or plans to), used for payoff projection.
    var minimumPayment: Decimal
    var notes: String?
    var isArchived: Bool
    var createdAt: Date

    /// Transactions the user has assigned to this debt (payments and charges). Deleting the debt
    /// nullifies the link on each transaction rather than deleting the transactions themselves.
    @Relationship(deleteRule: .nullify, inverse: \Transaction.debt)
    var transactions: [Transaction] = []

    init(
        name: String,
        kind: DebtKind,
        currentBalance: Decimal,
        annualInterestRate: Double = 0,
        minimumPayment: Decimal = 0,
        notes: String? = nil,
        isArchived: Bool = false
    ) {
        self.name = name
        self.kind = kind
        self.currentBalance = currentBalance
        self.annualInterestRate = annualInterestRate
        self.minimumPayment = minimumPayment
        self.notes = notes
        self.isArchived = isArchived
        self.createdAt = .now
    }
}
