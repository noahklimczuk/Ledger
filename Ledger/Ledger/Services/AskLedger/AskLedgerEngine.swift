import Foundation

/// Ask Ledger's on-device brain. Classifies a question by intent and answers it from the user's real
/// `AskLedgerContext` with a structured, advisor-style response — metrics, insights, charts,
/// forecasts — plus suggested actions and follow-ups. Deterministic and private: nothing leaves the
/// device, and every number is the user's own.
@MainActor
struct AskLedgerEngine {
    let context: AskLedgerContext

    /// The prompt cards on the landing screen.
    static let suggestedPrompts: [(icon: String, text: String)] = [
        ("cart.fill", "Can I afford a $200 purchase?"),
        ("chart.pie.fill", "Explain this month's spending"),
        ("scissors", "Where can I cut expenses?"),
        ("banknote.fill", "How much should I save?"),
        ("calendar", "Predict next month's cash flow"),
        ("repeat", "Review my subscriptions"),
        ("target", "Am I on track for my goals?"),
        ("heart.text.square.fill", "How healthy are my finances?"),
    ]

    func respond(to question: String) -> AskLedgerResponse {
        guard context.hasData else { return emptyResponse() }
        let q = question.lowercased()
        if q.containsAny("afford", "can i buy", "should i buy", "worth it") { return affordResponse(question) }
        if q.containsAny("subscription", "recurring") { return subscriptionsResponse() }
        if q.containsAny("cut", "reduce", "save money", "spend less", "trim") { return cutResponse() }
        if q.containsAny("overspend", "overspent", "over budget", "why did i") { return overspendResponse() }
        if q.containsAny("forecast", "next month", "cash flow", "predict", "cashflow", "upcoming") { return forecastResponse() }
        if q.containsAny("goal", "vacation", "trip", "save for", "on track") { return goalsResponse(question) }
        if q.containsAny("how much", "should i save", "savings rate", "saving") { return saveResponse() }
        if q.containsAny("healthy", "health", "wellness", "score", "how am i", "doing") { return wellnessResponse() }
        if q.containsAny("spend", "spending", "explain", "where did", "money go", "this month") { return spendingResponse() }
        return overviewResponse()
    }

    // MARK: - Intents

    private func overviewResponse() -> AskLedgerResponse {
        var r = AskLedgerResponse()
        r.blocks = [
            .headline("Here's where you stand"),
            .metrics([
                AskLedgerMetric(label: "Balance", value: m(context.totalBalance)),
                AskLedgerMetric(label: "Safe to spend", value: m(context.safeToSpend), caption: "\(context.daysLeftInMonth) days left", tone: context.safeToSpend >= 0 ? .positive : .caution),
                AskLedgerMetric(label: "\(context.monthName) net", value: signed(context.monthNet), tone: context.monthNet >= 0 ? .positive : .caution),
            ]),
            .insight(AskLedgerInsightItem(
                title: "\(context.wellness.state) \(context.wellness.stateEmoji)",
                message: context.wellness.summary,
                systemImage: "heart.text.square.fill",
                tone: .positive)),
            .paragraph("Ask me anything about your money — I'll answer from your real numbers."),
        ]
        r.actions = [route("See analytics", "chart.bar.xaxis", .analytics), ask("Where can I cut expenses?", "scissors")]
        r.followUps = ["Explain this month's spending", "Predict next month's cash flow", "How healthy are my finances?"]
        return r
    }

    private func affordResponse(_ question: String) -> AskLedgerResponse {
        var r = AskLedgerResponse()
        guard let amount = firstAmount(in: question) else {
            r.blocks = [
                .paragraph("Happy to help you decide. How much is the purchase? You've got \(m(context.safeToSpend)) of safe-to-spend room this month after bills and budgets."),
                .metrics([AskLedgerMetric(label: "Safe to spend", value: m(context.safeToSpend), caption: "\(context.daysLeftInMonth) days left", tone: context.safeToSpend >= 0 ? .positive : .caution)]),
            ]
            r.followUps = ["Can I afford a $100 purchase?", "Where can I cut expenses?"]
            return r
        }
        let after = context.safeToSpend - amount
        if after >= 0 {
            r.blocks = [
                .headline("Yes — you can afford it 🌿"),
                .metrics([
                    AskLedgerMetric(label: "Purchase", value: m(amount)),
                    AskLedgerMetric(label: "Left after", value: m(after), caption: "safe to spend", tone: .positive),
                ]),
                .paragraph("Buying this leaves \(m(after)) of breathing room for the rest of \(context.monthName), on top of your budgets and reserved bills. No stress."),
            ]
        } else {
            r.blocks = [
                .headline("It'd be a stretch this month"),
                .metrics([
                    AskLedgerMetric(label: "Purchase", value: m(amount)),
                    AskLedgerMetric(label: "Over by", value: m(-after), tone: .caution),
                ]),
                .paragraph("This is \(m(-after)) more than your \(m(context.safeToSpend)) of safe-to-spend room. Waiting until next month — or trimming a little from \(topCategoryName()) — would clear the way without touching your plan."),
            ]
        }
        r.actions = [ask("Where can I cut expenses?", "scissors"), route("See analytics", "chart.bar.xaxis", .analytics)]
        r.followUps = ["Predict next month's cash flow", "How much should I save?"]
        return r
    }

    private func spendingResponse() -> AskLedgerResponse {
        var r = AskLedgerResponse()
        let top = Array(context.categoriesThisMonth.prefix(6))
        r.blocks.append(.headline("Where your money went in \(context.monthName)"))
        if !top.isEmpty {
            let maxAmount = dv(top[0].amount)
            r.blocks.append(.bars(title: "Top categories", bars: top.map {
                AskLedgerBar(label: $0.name, value: maxAmount > 0 ? dv($0.amount) / maxAmount : 0, valueText: m($0.amount))
            }))
        }
        var summary = "You've spent \(m(context.monthSpending)) so far this month"
        if let first = top.first { summary += ", most of it on \(first.name.lowercased()) (\(m(first.amount)))." } else { summary += "." }
        r.blocks.append(.paragraph(summary))
        if let movement = biggestMovement() {
            r.blocks.append(.insight(movement))
        }
        r.actions = [route("Open analytics", "chart.bar.xaxis", .analytics), ask("Where can I cut expenses?", "scissors")]
        r.followUps = ["Am I over budget anywhere?", "Predict next month's cash flow"]
        return r
    }

    private func overspendResponse() -> AskLedgerResponse {
        var r = AskLedgerResponse()
        let over = context.budgetLines.filter { $0.spent > $0.allocated }
        if context.budgetLines.isEmpty {
            r.blocks = [
                .paragraph("You haven't set budgets yet, so nothing's technically over — but your biggest area is \(topCategoryName()) at \(m(context.categoriesThisMonth.first?.amount ?? 0)). Setting a few budgets makes overspending impossible to miss."),
            ]
            r.actions = [route("See analytics", "chart.bar.xaxis", .analytics)]
            r.followUps = ["Explain this month's spending", "Where can I cut expenses?"]
            return r
        }
        if over.isEmpty {
            r.blocks = [
                .insight(AskLedgerInsightItem(title: "Nothing's over budget", message: "Every category is inside its plan this month — nicely done. Keep an eye on \(context.budgetLines.first?.name ?? "your top category"), which is closest to the line.", systemImage: "checkmark.seal.fill", tone: .positive)),
            ]
        } else {
            r.blocks.append(.headline("A couple of categories ran over"))
            r.blocks.append(.budget(title: "Over budget", lines: over.prefix(4).map { budgetLine($0) }))
            let total = over.reduce(Decimal(0)) { $0 + ($1.spent - $1.allocated) }
            r.blocks.append(.paragraph("You're \(m(total)) over across \(over.count == 1 ? "one category" : "\(over.count) categories") — the rest of your plan held. Trimming \(over[0].name.lowercased()) a little next month clears it. This happens; you're not off track."))
        }
        r.actions = [route("See analytics", "chart.bar.xaxis", .analytics), ask("Where can I cut expenses?", "scissors")]
        r.followUps = ["How much should I save?", "Predict next month's cash flow"]
        return r
    }

    private func cutResponse() -> AskLedgerResponse {
        var r = AskLedgerResponse()
        r.blocks.append(.headline("A few painless places to find room"))
        var insights: [AskLedgerInsightItem] = []
        if context.subscriptionMonthly > 0, let priciest = context.subscriptions.first {
            insights.append(AskLedgerInsightItem(
                title: "Trim a subscription",
                message: "Subscriptions run \(m(context.subscriptionMonthly))/mo. Dropping just \(priciest.name) (\(m(priciest.monthly))/mo) frees \(mD(priciest.annual))/yr.",
                systemImage: "repeat", tone: .info))
        }
        if let movement = biggestMovement(), movement.tone == .caution {
            insights.append(movement)
        } else if let top = context.categoriesThisMonth.first {
            insights.append(AskLedgerInsightItem(title: "Ease off \(top.name.lowercased())", message: "\(top.name) is your largest category at \(m(top.amount)) this month. A 10% trim is \(mD(dv(top.amount) * 0.1)) back in your pocket.", systemImage: "arrow.down.right", tone: .info))
        }
        insights.append(AskLedgerInsightItem(title: "Automate a little", message: "Moving \(m(15)) a week into savings is barely noticeable and adds up to \(mD(780))/yr.", systemImage: "arrow.triangle.branch", tone: .positive))
        for insight in insights { r.blocks.append(.insight(insight)) }
        r.actions = [route("Review subscriptions", "repeat", .subscriptions), route("See analytics", "chart.bar.xaxis", .analytics)]
        r.followUps = ["Review my subscriptions", "How much should I save?"]
        return r
    }

    private func saveResponse() -> AskLedgerResponse {
        var r = AskLedgerResponse()
        let rate = max(context.savingsRate, 0)
        let target = 0.20
        let targetMonthly = context.monthIncome * Decimal(target)
        let currentMonthly = max(context.monthNet, 0)
        r.blocks.append(.headline("Saving \(pct(rate)) of your income"))
        r.blocks.append(.metrics([
            AskLedgerMetric(label: "Now", value: pct(rate), tone: rate >= target ? .positive : .neutral),
            AskLedgerMetric(label: "Healthy target", value: pct(target), tone: .info),
            AskLedgerMetric(label: "20% is", value: m(targetMonthly), caption: "per month", tone: .info),
        ]))
        if rate >= target {
            r.blocks.append(.paragraph("You're already past the 20% mark — genuinely strong. Anything extra could go straight to your emergency fund or a goal."))
        } else {
            let gap = targetMonthly - currentMonthly
            r.blocks.append(.paragraph("A healthy target is 20%. You're setting aside \(m(currentMonthly))/mo now; nudging to 20% means about \(m(max(gap, 0))) more. You have \(m(context.safeToSpend)) of safe-to-spend room to pull from."))
        }
        r.blocks.append(.forecast(AskLedgerForecast(headline: "A year at each pace", rows: [
            AskLedgerForecastRow(label: "At \(pct(rate)) (now)", value: m(currentMonthly * 12)),
            AskLedgerForecastRow(label: "At 20%", value: m(targetMonthly * 12), tone: .positive),
        ])))
        r.actions = [route("See my goals", "target", .goals), ask("Where can I cut expenses?", "scissors")]
        r.followUps = ["Am I on track for my goals?", "How healthy are my finances?"]
        return r
    }

    private func forecastResponse() -> AskLedgerResponse {
        var r = AskLedgerResponse()
        let projectedNet = context.monthIncome - context.projectedSpending
        r.blocks.append(.headline("Your \(context.monthName) forecast"))
        r.blocks.append(.forecast(AskLedgerForecast(headline: "Projected month-end", rows: [
            AskLedgerForecastRow(label: "Expected income", value: m(context.monthIncome), tone: .positive),
            AskLedgerForecastRow(label: "Projected spending", value: m(context.projectedSpending)),
            AskLedgerForecastRow(label: "Reserved for bills", value: m(context.reservedForBills)),
            AskLedgerForecastRow(label: "Projected leftover", value: signed(projectedNet), tone: projectedNet >= 0 ? .positive : .caution),
        ], tone: projectedNet >= 0 ? .positive : .caution)))
        if context.reservedForBills > context.safeToSpend, context.reservedForBills > 0 {
            r.blocks.append(.insight(AskLedgerInsightItem(title: "Bills land before month-end", message: "\(m(context.reservedForBills)) of bills and subscriptions are still due this month — keep that set aside and you'll coast in comfortably.", systemImage: "calendar.badge.clock", tone: .caution)))
        } else {
            r.blocks.append(.paragraph("At your current pace you'll finish \(context.monthName) \(projectedNet >= 0 ? "ahead by \(m(projectedNet))" : "down \(m(-projectedNet))"). \(projectedNet >= 0 ? "That's money you can move to savings." : "Easing off now brings it back to even.")"))
        }
        r.actions = [route("Open analytics", "chart.bar.xaxis", .analytics), route("Review subscriptions", "repeat", .subscriptions)]
        r.followUps = ["Where can I cut expenses?", "How much should I save?"]
        return r
    }

    private func subscriptionsResponse() -> AskLedgerResponse {
        var r = AskLedgerResponse()
        guard !context.subscriptions.isEmpty else {
            r.blocks = [.paragraph("I haven't spotted any recurring subscriptions in your history yet. As more transactions come in, I'll detect them automatically and flag anything worth a look.")]
            r.followUps = ["Explain this month's spending", "Where can I cut expenses?"]
            return r
        }
        let lines = context.subscriptions.prefix(8).map { sub -> AskLedgerSubLine in
            AskLedgerSubLine(name: sub.name, amountText: m(sub.monthly), cadence: sub.cadence, flag: duplicateFlag(for: sub))
        }
        r.blocks.append(.headline("Your subscriptions"))
        r.blocks.append(.subscriptions(monthly: m(context.subscriptionMonthly), lines: Array(lines)))
        if let priciest = context.subscriptions.first {
            r.blocks.append(.insight(AskLedgerInsightItem(title: "Biggest one to reconsider", message: "\(priciest.name) is \(mD(priciest.annual))/yr. If it's not earning its keep, cancelling it is your fastest win.", systemImage: "arrow.down.circle", tone: .info)))
        }
        r.actions = [route("Manage subscriptions", "repeat", .subscriptions), ask("Where can I cut expenses?", "scissors")]
        r.followUps = ["How much should I save?", "Predict next month's cash flow"]
        return r
    }

    private func goalsResponse(_ question: String) -> AskLedgerResponse {
        var r = AskLedgerResponse()
        guard !context.goals.isEmpty else {
            r.blocks = [
                .paragraph("You haven't planted a savings goal yet. Give me a target and a date and I'll map the pace — for example, saving \(m(3000)) for a trip in 10 months is \(m(300))/mo."),
            ]
            r.actions = [route("Create a goal", "target", .goals)]
            r.followUps = ["How much should I save?", "How healthy are my finances?"]
            return r
        }
        let q = question.lowercased()
        let picked = context.goals.first { q.contains($0.name.lowercased()) } ?? context.goals.max { $0.progress < $1.progress }!
        r.blocks.append(.headline(picked.name))
        r.blocks.append(.progress(title: "\(m(picked.saved)) of \(m(picked.target))", fraction: picked.progress, caption: "\(Int(picked.progress * 100))% grown", tone: .positive))
        if let monthly = picked.requiredMonthly, let date = picked.targetDate {
            let onPace = context.monthNet >= monthly
            r.blocks.append(.paragraph("To reach it by \(DateFormatting.medium(date)) you'd set aside \(m(monthly))/mo. \(onPace ? "You're saving more than that right now — you're ahead. 🌿" : "That's a touch above your current pace, but within reach with a small trim.")"))
        } else {
            r.blocks.append(.paragraph("\(m(picked.target - picked.saved)) to go. Give it a target date and I'll pace it out for you."))
        }
        if context.goals.count > 1 {
            r.blocks.append(.paragraph("You're tending \(context.goals.count) goals in total — every contribution helps them grow."))
        }
        r.actions = [route("See all goals", "target", .goals), ask("How much should I save?", "banknote.fill")]
        r.followUps = ["Where can I cut expenses?", "How healthy are my finances?"]
        return r
    }

    private func wellnessResponse() -> AskLedgerResponse {
        var r = AskLedgerResponse()
        let w = context.wellness
        r.blocks.append(.progress(title: "Financial wellness", fraction: Double(w.score) / 100, caption: "\(w.state) \(w.stateEmoji)", tone: .positive))
        if let strong = w.strongest {
            r.blocks.append(.insight(AskLedgerInsightItem(title: "What's carrying you", message: "\(strong.name): \(strong.valueText). \(strong.detail)", systemImage: "arrow.up.forward", tone: .positive)))
        }
        if let tend = w.toTend.first {
            r.blocks.append(.insight(AskLedgerInsightItem(title: "One thing to tend", message: "\(tend.name): \(tend.valueText). \(tend.detail)", systemImage: "leaf.fill", tone: .caution)))
        }
        r.blocks.append(.paragraph(w.summary))
        r.actions = [route("Open wellness", "heart.text.square.fill", .wellness), ask("Where can I cut expenses?", "scissors")]
        r.followUps = ["Predict next month's cash flow", "Am I on track for my goals?"]
        return r
    }

    private func emptyResponse() -> AskLedgerResponse {
        var r = AskLedgerResponse()
        r.blocks = [.paragraph("Add an account or a few transactions and I'll answer with your real numbers — what you can afford, where to cut, how much to save, and what's coming next.")]
        r.followUps = ["How healthy are my finances?", "How much should I save?"]
        return r
    }

    // MARK: - Helpers

    private func biggestMovement() -> AskLedgerInsightItem? {
        var best: (name: String, delta: Double)?
        for cat in context.categoriesThisMonth.prefix(8) {
            let last = dv(context.categoriesLastMonth[cat.name] ?? 0)
            let delta = dv(cat.amount) - last
            if last > 40, abs(delta) >= 40, abs(delta) > abs(best?.delta ?? 0) {
                best = (cat.name, delta)
            }
        }
        guard let best else { return nil }
        let up = best.delta > 0
        return AskLedgerInsightItem(
            title: up ? "\(best.name) is up this month" : "\(best.name) is down this month",
            message: "\(best.name) is \(mD(abs(best.delta))) \(up ? "higher" : "lower") than last month.\(up ? " Worth a glance if it wasn't planned." : " Nice trimming.")",
            systemImage: up ? "arrow.up.right" : "arrow.down.right",
            tone: up ? .caution : .positive)
    }

    private func duplicateFlag(for sub: AskLedgerContext.Subscription) -> String? {
        let peers = context.subscriptions.filter {
            $0.name != sub.name && $0.cadence == sub.cadence &&
            abs(dv($0.monthly) - dv(sub.monthly)) / max(dv(sub.monthly), 1) <= 0.05
        }
        return peers.isEmpty ? nil : "possible duplicate"
    }

    private func budgetLine(_ line: AskLedgerContext.BudgetLine) -> AskLedgerBudgetLine {
        let progress = dv(line.allocated) > 0 ? dv(line.spent) / dv(line.allocated) : 1
        return AskLedgerBudgetLine(name: line.name, spentText: m(line.spent), allocatedText: m(line.allocated), progress: progress, isOver: line.spent > line.allocated)
    }

    private func topCategoryName() -> String { context.categoriesThisMonth.first?.name.lowercased() ?? "discretionary spending" }

    private func route(_ title: String, _ icon: String, _ route: AskLedgerRoute) -> AskLedgerAction {
        AskLedgerAction(title: title, systemImage: icon, kind: .route(route))
    }
    private func ask(_ prompt: String, _ icon: String) -> AskLedgerAction {
        AskLedgerAction(title: prompt, systemImage: icon, kind: .ask(prompt))
    }

    private func firstAmount(in text: String) -> Decimal? {
        var token = ""
        var tokens: [String] = []
        for ch in text {
            if ch.isNumber || ch == "." { token.append(ch) }
            else if ch == "," { continue }
            else { if !token.isEmpty { tokens.append(token); token = "" } }
        }
        if !token.isEmpty { tokens.append(token) }
        for t in tokens { if let d = Double(t), d > 0 { return Decimal(d) } }
        return nil
    }

    private func dv(_ value: Decimal) -> Double { (value as NSDecimalNumber).doubleValue }
    private func pct(_ x: Double) -> String { "\(Int((x * 100).rounded()))%" }
    private func m(_ value: Decimal) -> String {
        var input = value, rounded = Decimal()
        NSDecimalRound(&rounded, &input, 0, .plain)
        return CurrencyFormatter.string(from: rounded)
    }
    private func mD(_ value: Double) -> String { m(Decimal(value)) }
    private func signed(_ value: Decimal) -> String { (value >= 0 ? "+" : "") + m(value) }
}

private extension String {
    func containsAny(_ words: String...) -> Bool { words.contains { self.contains($0) } }
}
