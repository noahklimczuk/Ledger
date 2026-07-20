import Foundation
import SwiftData

/// One contributing factor in the Financial Wellness score — what it is, its current reading, how
/// much it helps or hurts, and a plain-language note. Rendered as a card on the Wellness screen.
struct WellnessFactor: Identifiable {
    let id = UUID()
    let name: String
    /// The current reading, e.g. "34%", "4.1 months", "$1,842".
    let valueText: String
    /// Display label for its contribution, e.g. "+22 pts" (helping) or "−7 pts" (a cost).
    let pointsLabel: String
    /// 0…1 strength of this factor, for its meter fill.
    let fraction: Double
    /// True when this factor is pulling the score up; false when it's the thing to tend.
    let isHelping: Bool
    /// A short note — encouragement when helping, guidance when it's the thing to tend.
    let detail: String
    let systemImage: String
}

/// The computed Financial Wellness result: a 0–100 score, a plain-language state, the factors behind
/// it, and a one-line summary. Deterministic and fully on-device — nothing leaves the phone.
struct WellnessResult {
    let score: Int
    let summary: String
    let factors: [WellnessFactor]

    /// A calm, human label for the current band.
    var state: String {
        switch score {
        case 85...:    "Flourishing"
        case 70..<85:  "Thriving"
        case 50..<70:  "Steady"
        case 30..<50:  "Finding footing"
        default:       "Needs some care"
        }
    }

    var stateEmoji: String {
        switch score {
        case 70...:   "🌿"
        case 50..<70: "🌱"
        default:      "💛"
        }
    }

    /// The factors worth tending, weakest first — drives the "What to tend" section.
    var toTend: [WellnessFactor] {
        factors.filter { !$0.isHelping }.sorted { $0.fraction < $1.fraction }
    }

    /// The factor doing the most good, for the summary line.
    var strongest: WellnessFactor? {
        factors.filter { $0.isHelping }.max { $0.fraction < $1.fraction }
    }

    static let empty = WellnessResult(score: 0, summary: "Add an account and a few transactions to grow your wellness score.", factors: [])
}

/// Computes the Financial Wellness score from the user's own data. `compute` is pure math over
/// derived inputs (easy to reason about and unit-test); `evaluate` gathers those inputs from a
/// `ModelContext`. Weights sum to 100 and the score is normalized by whichever factors apply, so a
/// user with no budget set still gets a fair score from the factors that do.
@MainActor
enum WellnessScore {
    // Component weights (of 100).
    private static let wSavings   = 30.0
    private static let wEmergency = 25.0
    private static let wDebt      = 20.0
    private static let wBudget    = 15.0
    private static let wPace      = 10.0

    // MARK: Inputs

    struct Inputs {
        /// Monthly (income − spending) / income, this month. May be negative.
        var savingsRate: Double
        /// Liquid savings ÷ average monthly expenses.
        var emergencyMonths: Double
        var liquidSavings: Double
        var totalDebt: Double
        var annualIncome: Double
        /// This month's spending ÷ total budget. Nil when no budget is set.
        var budgetSpentRatio: Double?
        /// Projected month-end spending ÷ budget (or ÷ typical spend). Nil when unknown.
        var spendingPaceRatio: Double?
    }

    // MARK: Pure scoring

    static func compute(_ input: Inputs) -> WellnessResult {
        var earnedSum = 0.0
        var weightSum = 0.0
        var factors: [WellnessFactor] = []

        func add(weight: Double, fraction: Double, factor: (Double, Double) -> WellnessFactor) {
            let f = clamp(fraction)
            let earned = weight * f
            earnedSum += earned
            weightSum += weight
            factors.append(factor(f, earned))
        }

        // Savings rate — target 20%.
        add(weight: wSavings, fraction: input.savingsRate / 0.20) { f, earned in
            make("Savings rate", value: percent(input.savingsRate), f: f, earned: earned, weight: wSavings,
                 help: "Well above the 20% target — this is doing the most for you.",
                 tend: "Aim to keep at least 20% of income. A small automatic transfer on payday helps.",
                 icon: "leaf.fill")
        }

        // Emergency fund — full cushion at ~6 months of expenses.
        add(weight: wEmergency, fraction: input.emergencyMonths / 6.0) { f, earned in
            make("Emergency fund", value: monthsText(input.emergencyMonths), f: f, earned: earned, weight: wEmergency,
                 help: "A solid cushion set aside for the unexpected.",
                 tend: "Building toward ~6 months of expenses steadies everything else.",
                 icon: "shield.fill")
        }

        // Debt load — full when debt-free relative to income.
        let debtToIncome = input.annualIncome > 0 ? input.totalDebt / input.annualIncome : (input.totalDebt > 0 ? 1 : 0)
        add(weight: wDebt, fraction: 1 - debtToIncome) { f, earned in
            make("Debt load", value: input.totalDebt <= 0 ? "Debt-free" : money(input.totalDebt), f: f, earned: earned, weight: wDebt,
                 help: input.totalDebt <= 0 ? "No tracked debt — nothing dragging on your progress." : "Manageable next to your income, and shrinking.",
                 tend: "Chipping away at the highest-rate balance frees up room fastest.",
                 icon: "creditcard.fill")
        }

        // Budget adherence — full when within budget.
        if let ratio = input.budgetSpentRatio {
            let fraction = ratio <= 1 ? 1 : 1 - (ratio - 1) * 2
            add(weight: wBudget, fraction: fraction) { f, earned in
                make("Budget adherence", value: "\(Int((ratio * 100).rounded()))% of budget", f: f, earned: earned, weight: wBudget,
                     help: "You're spending within the plan you set.",
                     tend: "A category or two is running over. A quick rebalance keeps things green.",
                     icon: "chart.pie.fill")
            }
        }

        // Spending pace — full when projected to land within budget/typical.
        if let pace = input.spendingPaceRatio {
            let fraction = pace <= 1 ? 1 : 1 - (pace - 1) * 2
            let overPct = Int(((pace - 1) * 100).rounded())
            add(weight: wPace, fraction: fraction) { f, earned in
                make("Spending pace", value: pace <= 1 ? "On pace" : "+\(overPct)% pace", f: f, earned: earned, weight: wPace,
                     help: "Your day-to-day pace lands you on plan by month end.",
                     tend: "You're spending a little fast this month — easing off now recovers it.",
                     icon: "speedometer")
            }
        }

        let score = weightSum > 0 ? Int((earnedSum / weightSum * 100).rounded()) : 0
        let clampedScore = min(max(score, 0), 100)
        return WellnessResult(score: clampedScore, summary: summary(score: clampedScore, factors: factors), factors: factors)
    }

    // MARK: Gather from the store

    static func evaluate(modelContext: ModelContext, now: Date = .now, calendar: Calendar = .current) -> WellnessResult {
        let accounts = ((try? modelContext.fetch(FetchDescriptor<Account>(predicate: #Predicate { !$0.isArchived }))) ?? [])
        let allTx = ((try? modelContext.fetch(FetchDescriptor<Transaction>())) ?? [])
            .filter { $0.countsTowardTotals && !$0.isTransfer }

        let monthStart = Budget.normalize(now)
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart

        func spending(in range: Range<Date>) -> Double {
            d(allTx.filter { range.contains($0.date) && $0.amount < 0 }.reduce(Decimal(0)) { $0 + (-$1.amount) })
        }
        func income(in range: Range<Date>) -> Double {
            d(allTx.filter { range.contains($0.date) && $0.amount > 0 }.reduce(Decimal(0)) { $0 + $1.amount })
        }

        let monthSpending = spending(in: monthStart..<monthEnd)
        let monthIncome = income(in: monthStart..<monthEnd)

        // Trailing 3 full months for stable baselines.
        let priorStart = calendar.date(byAdding: .month, value: -3, to: monthStart) ?? monthStart
        let priorSpend = spending(in: priorStart..<monthStart)
        let priorIncome = income(in: priorStart..<monthStart)
        let avgMonthlyExpenses = priorSpend > 0 ? priorSpend / 3 : monthSpending
        let avgMonthlyIncome = priorIncome > 0 ? priorIncome / 3 : monthIncome
        let annualIncome = (avgMonthlyIncome > 0 ? avgMonthlyIncome : monthIncome) * 12

        // Liquid savings: savings-type accounts, or an emergency-fund goal, whichever is larger.
        let savingsAccounts = d(accounts.filter { $0.type == .savings }.reduce(Decimal(0)) { $0 + max($1.currentBalance, 0) })
        let goals = ((try? modelContext.fetch(FetchDescriptor<SavingsGoal>(predicate: #Predicate { !$0.isArchived }))) ?? [])
        let emergencyGoal = goals.first { $0.name.lowercased().contains("emerg") }
        let liquidSavings = max(savingsAccounts, d(emergencyGoal?.savedAmount ?? 0))
        let emergencyMonths = avgMonthlyExpenses > 0 ? liquidSavings / avgMonthlyExpenses : (liquidSavings > 0 ? 6 : 0)

        // Debt: tracked debts + amounts owed on credit accounts (stored negative).
        let debts = ((try? modelContext.fetch(FetchDescriptor<Debt>(predicate: #Predicate { !$0.isArchived }))) ?? [])
        let trackedDebt = d(debts.reduce(Decimal(0)) { $0 + max($1.currentBalance, 0) })
        let creditOwed = d(accounts.filter { $0.type == .credit }.reduce(Decimal(0)) { $0 + max(-$1.currentBalance, 0) })
        let totalDebt = trackedDebt + creditOwed

        // Budget for the month.
        let budgets = ((try? modelContext.fetch(FetchDescriptor<Budget>(predicate: #Predicate { $0.month == monthStart }))) ?? [])
        let budgetTotal = d(budgets.reduce(Decimal(0)) { $0 + $1.allocatedAmount })

        let daysInMonth = Double(calendar.range(of: .day, in: .month, for: now)?.count ?? 30)
        let elapsed = Double(min(max(calendar.component(.day, from: now), 1), Int(daysInMonth)))
        let projected = elapsed > 0 ? monthSpending * daysInMonth / elapsed : monthSpending

        let savingsRate = monthIncome > 0 ? (monthIncome - monthSpending) / monthIncome : 0
        let budgetSpentRatio: Double? = budgetTotal > 0 ? monthSpending / budgetTotal : nil
        let spendingPaceRatio: Double? = budgetTotal > 0 ? projected / budgetTotal
            : (avgMonthlyExpenses > 0 ? projected / avgMonthlyExpenses : nil)

        return compute(Inputs(
            savingsRate: savingsRate,
            emergencyMonths: emergencyMonths,
            liquidSavings: liquidSavings,
            totalDebt: totalDebt,
            annualIncome: annualIncome,
            budgetSpentRatio: budgetSpentRatio,
            spendingPaceRatio: spendingPaceRatio
        ))
    }

    // MARK: Helpers

    private static func make(
        _ name: String, value: String, f: Double, earned: Double, weight: Double,
        help: String, tend: String, icon: String
    ) -> WellnessFactor {
        let helping = f >= 0.6
        let label = helping ? "+\(Int(earned.rounded())) pts" : "−\(Int((weight - earned).rounded())) pts"
        return WellnessFactor(
            name: name, valueText: value, pointsLabel: label, fraction: f,
            isHelping: helping, detail: helping ? help : tend, systemImage: icon
        )
    }

    private static func summary(score: Int, factors: [WellnessFactor]) -> String {
        guard !factors.isEmpty else { return WellnessResult.empty.summary }
        let strongest = factors.filter { $0.isHelping }.max { $0.fraction < $1.fraction }
        let tend = factors.filter { !$0.isHelping }.min { $0.fraction < $1.fraction }
        switch (strongest, tend) {
        case let (s?, t?):
            return "\(s.name) is carrying you. The one thing to tend is \(t.name.lowercased())."
        case let (s?, nil):
            return "\(s.name) leads the way and nothing's dragging — keep it up."
        case let (nil, t?):
            return "A good start. Focus next on \(t.name.lowercased())."
        default:
            return "You're building healthy habits."
        }
    }

    private static func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
    private static func d(_ value: Decimal) -> Double { (value as NSDecimalNumber).doubleValue }
    private static func percent(_ rate: Double) -> String { "\(Int((rate * 100).rounded()))%" }
    private static func money(_ value: Double) -> String { CurrencyFormatter.string(from: Decimal(value.rounded())) }
    private static func monthsText(_ months: Double) -> String {
        if months >= 6 { return "6+ months" }
        return String(format: "%.1f months", months)
    }
}
