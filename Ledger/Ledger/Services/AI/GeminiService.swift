import Foundation

/// Minimal hand-rolled client for Google's Gemini API (no SDK dependency, same approach as
/// `WealthsimpleAPIClient`). It powers two features: turning the on-device budget summary and
/// recent transaction history into suggested amounts with a plain-English rationale, and the
/// multi-turn financial-advisor chat, which can also *create* the month's budget through a
/// function-calling tool.
///
/// What goes over the wire: aggregated totals plus recent transaction lines (date, amount,
/// category, merchant). Account names, balances, notes, and receipts are never sent.
///
/// Gemini has a genuinely free tier (no credit card — just a Google account at
/// aistudio.google.com), which is why it replaced the paid Anthropic path. The key comes from the
/// user's own Google AI Studio account, is stored in the Keychain only, and the feature degrades
/// to the on-device numbers whenever the key or network is missing.
struct GeminiService: Sendable {
    enum ServiceError: Error, LocalizedError {
        case missingAPIKey
        case invalidResponse
        case server(status: Int, message: String?)
        case blocked
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                "Add your free Google Gemini API key to get AI-tailored suggestions."
            case .invalidResponse:
                "The AI service returned an unexpected response."
            case .server(let status, let message):
                "AI request failed (\(status)): \(message ?? "no details")"
            case .blocked:
                "The AI declined this request."
            case .emptyResponse:
                "The AI returned no suggestions."
            }
        }
    }

    /// One category's AI-suggested budget.
    struct SuggestedCategory: Decodable {
        let name: String
        let amount: Double
        let rationale: String
    }

    /// The AI-proposed monthly savings set-aside, sized to the income-vs-spending gap.
    struct SuggestedSavings: Decodable {
        let amount: Double
        let rationale: String
    }

    struct Suggestion: Decodable {
        let categories: [SuggestedCategory]
        let savings: SuggestedSavings?
        /// Plain-English overview of the proposed plan.
        let summary: String
    }

    /// Models tried in order, best-first. Gemini 3.5 Flash is the most capable Flash model, but its
    /// shared free pool gets saturated and returns 503 "high demand" that short retries can't clear;
    /// when it stays unavailable we fall back to the lighter, less-contended 3.1 Flash-Lite so the
    /// request still completes. Both are current 3.x models — the 2.5 family is now 404 "no longer
    /// available to new users" on freshly created projects, so it must NOT be in this chain. Both
    /// support the structured (schema-constrained) output and function calling this feature needs.
    private static let modelFallbackChain = ["gemini-3.5-flash", "gemini-3.1-flash-lite"]
    static let apiKeyKeychainKey = "gemini.apiKey"

    private static func endpoint(for model: String) -> URL {
        URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    static var storedAPIKey: String? {
        KeychainService.getString(forKey: apiKeyKeychainKey)
    }

    static func setAPIKey(_ key: String?) {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            try? KeychainService.set(trimmed, forKey: apiKeyKeychainKey)
        } else {
            KeychainService.delete(forKey: apiKeyKeychainKey)
        }
    }

    /// Asks the model to propose per-category budgets plus a savings amount from the summary and
    /// recent transactions. A response schema (`generationConfig.responseSchema` +
    /// `application/json`) guarantees the reply is valid JSON matching our shape.
    func suggestBudget(from summary: BudgetSuggestionService.Summary, apiKey: String) async throws -> Suggestion {
        let body: [String: Any] = [
            "contents": [
                ["parts": [["text": Self.prompt(for: summary)]]]
            ],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": Self.outputSchema
            ]
        ]
        let text = try await generateText(body: body, apiKey: apiKey)
        guard let jsonData = text.data(using: .utf8) else { throw ServiceError.emptyResponse }
        let suggestion = try JSONDecoder().decode(Suggestion.self, from: jsonData)
        guard !suggestion.categories.isEmpty else { throw ServiceError.emptyResponse }
        return suggestion
    }

    // MARK: - Advisor chat

    /// One turn of an advisor conversation. Beyond plain text, turns carry the function-calling
    /// round trip: the model's `create_budget` call and our result for it, both kept in history so
    /// follow-up questions have the full picture. A model turn holds text and call together —
    /// Gemini emits them in one candidate and expects them echoed back as one content, keeping the
    /// user/model alternation intact.
    enum ChatTurn: Sendable {
        case user(String)
        case model(text: String?, functionCall: FunctionCallEcho?)
        case functionResponse(name: String, responseJSON: String)
    }

    /// A model-issued function call as it gets echoed back into conversation history.
    struct FunctionCallEcho: Sendable {
        let name: String
        let argsJSON: String
    }

    /// A budget the model asked us to create via the `create_budget` tool.
    struct BudgetPlan: Sendable {
        struct PlanCategory: Sendable {
            let name: String
            let amount: Decimal
        }
        let categories: [PlanCategory]
        /// Monthly savings set-aside, proportional to the income-vs-spending gap.
        let savingsAmount: Decimal
        let summary: String?
        /// Target month as a raw "yyyy-MM" string from the model. `nil` means the conversation's
        /// month; a value lets the advisor budget a past or future month the user asked about.
        let month: String?
        /// Inclusive first/last month of a range ("yyyy-MM"), for vague requests that span several
        /// months ("the next three months", "January through March"). The same amounts apply to
        /// every month in the range. `nil` when a single `month` (or the conversation's month) is meant.
        let startMonth: String?
        let endMonth: String?
    }

    /// What one advisor round produced: text to show, and/or a budget plan to apply.
    struct AdvisorReply: Sendable {
        let text: String
        let budgetPlan: BudgetPlan?
        /// The call's raw arguments, echoed back into history alongside our function response.
        let budgetPlanArgsJSON: String?
    }

    /// Freeform advisor reply for the multi-turn financial-advisor chat. `system` carries the
    /// advisor persona plus the financial snapshot (budget totals and recent transactions);
    /// `history` is the running exchange, oldest first, ending with the user's latest question or
    /// our latest function response. The model may answer with text, a `create_budget` call, or
    /// both.
    func advise(system: String, history: [ChatTurn], apiKey: String) async throws -> AdvisorReply {
        var contents: [[String: Any]] = []
        for turn in history {
            switch turn {
            case .user(let text):
                contents.append(["role": "user", "parts": [["text": text]]])
            case .model(let text, let functionCall):
                var parts: [[String: Any]] = []
                if let text { parts.append(["text": text]) }
                if let functionCall {
                    let call: [String: Any] = ["name": functionCall.name, "args": Self.jsonObject(from: functionCall.argsJSON)]
                    parts.append(["functionCall": call])
                }
                contents.append(["role": "model", "parts": parts])
            case .functionResponse(let name, let responseJSON):
                let result: [String: Any] = ["name": name, "response": Self.jsonObject(from: responseJSON)]
                contents.append(["role": "user", "parts": [["functionResponse": result]]])
            }
        }
        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": system]]],
            "contents": contents,
            "tools": [["functionDeclarations": [Self.createBudgetDeclaration]]]
        ]
        let parts = try await generateParts(body: body, apiKey: apiKey)

        let text = parts.compactMap(\.text).joined()
        var plan: BudgetPlan?
        var argsJSON: String?
        if let call = parts.compactMap(\.functionCall).first(where: { $0.name == Self.createBudgetToolName }),
           let args = call.args {
            let categories = (args.categories ?? []).compactMap { item -> BudgetPlan.PlanCategory? in
                guard let name = item.name, let amount = item.amount, amount > 0 else { return nil }
                return BudgetPlan.PlanCategory(name: name, amount: Decimal(amount))
            }
            let savings = Decimal(max(args.savingsAmount ?? 0, 0))
            if !categories.isEmpty || savings > 0 {
                plan = BudgetPlan(
                    categories: categories,
                    savingsAmount: savings,
                    summary: args.summary,
                    month: args.month,
                    startMonth: args.startMonth,
                    endMonth: args.endMonth
                )
                argsJSON = Self.json(from: args)
            }
        }

        guard plan != nil || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServiceError.emptyResponse
        }
        return AdvisorReply(text: text, budgetPlan: plan, budgetPlanArgsJSON: argsJSON)
    }

    static let createBudgetToolName = "create_budget"

    /// The tool the advisor can call to actually build the user's monthly budget. Gemini's
    /// function-declaration schema is the same OpenAPI 3.0 subset as `outputSchema`.
    private static let createBudgetDeclaration: [String: Any] = [
        "name": createBudgetToolName,
        "description": "Create or update the user's category budgets. Target a single month (current, "
            + "past, or future) with `month`, or a span of months with `startMonth`/`endMonth` for vague "
            + "requests like \"the next three months\" or \"January through March\" — the same amounts "
            + "apply to every month in the range. Call this only when the user asks you to create, set, "
            + "or update their budget. Amounts are monthly Canadian-dollar totals. Include every category "
            + "to budget plus a monthly savings amount proportional to the gap between the month's income "
            + "and spending.",
        "parameters": [
            "type": "OBJECT",
            "properties": [
                "categories": [
                    "type": "ARRAY",
                    "items": [
                        "type": "OBJECT",
                        "properties": [
                            "name": ["type": "STRING", "description": "Exact name of one of the user's expense categories."],
                            "amount": ["type": "NUMBER", "description": "Monthly budget for the category."]
                        ] as [String: Any],
                        "required": ["name", "amount"]
                    ] as [String: Any]
                ] as [String: Any],
                "savingsAmount": [
                    "type": "NUMBER",
                    "description": "Monthly amount to set aside as savings, proportional to the gap between income and spending."
                ],
                "month": [
                    "type": "STRING",
                    "description": "Which single month to budget, as \"YYYY-MM\" (e.g. \"2026-03\"). May be a "
                        + "past or future month. Omit to use the month currently open in the app, or when "
                        + "budgeting a range via startMonth/endMonth."
                ],
                "startMonth": [
                    "type": "STRING",
                    "description": "First month of a range to budget, as \"YYYY-MM\", inclusive. Use with "
                        + "endMonth for requests spanning several months (e.g. \"the next three months\"). "
                        + "The same amounts are applied to every month in the range."
                ],
                "endMonth": [
                    "type": "STRING",
                    "description": "Last month of a range to budget, as \"YYYY-MM\", inclusive. Use with startMonth."
                ],
                "summary": ["type": "STRING", "description": "One or two sentences describing the plan."]
            ] as [String: Any],
            "required": ["categories", "savingsAmount"]
        ] as [String: Any]
    ]

    // MARK: - Shared transport

    /// HTTP statuses worth retrying: the model was momentarily overloaded (503), the server hiccuped
    /// (500/502/504), or we were briefly rate-limited (429/408). Gemini itself describes 503 demand
    /// spikes as "usually temporary," so a couple of backed-off retries turn most of them into a
    /// successful reply instead of a dead end. 4xx like 400 (bad request) or 403 (bad key) are not
    /// here — retrying those just repeats the same failure.
    private static let retryableStatuses: Set<Int> = [408, 429, 500, 502, 503, 504]
    /// Tries per model including the first, so one quick backed-off retry. Kept low because when a
    /// model stays overloaded we now fail over to the next model rather than hammer this one.
    private static let maxAttemptsPerModel = 2

    /// Shared `generateContent` call: POSTs `body`, and returns the first candidate's parts (text
    /// and/or function calls). Resilience has two layers — a short backoff retry for a momentary
    /// blip on one model, and a fall-through to the next model in the chain when one stays
    /// unavailable (the sustained-503 case). Non-retryable failures (bad request, bad key, safety
    /// block) surface immediately without burning through the other models.
    private func generateParts(body: [String: Any], apiKey: String) async throws -> [Part] {
        let payload = try JSONSerialization.data(withJSONObject: body)
        var lastError: Error?
        for (index, model) in Self.modelFallbackChain.enumerated() {
            let isLastModel = index == Self.modelFallbackChain.count - 1
            do {
                return try await generateWithRetry(payload: payload, apiKey: apiKey, model: model)
            } catch {
                // Fall to the next model when this one is overloaded (transient) OR unavailable to
                // this project (404 — e.g. a retired model). Anything else (bad request, bad key,
                // safety block) won't improve on a different model, so surface it now.
                guard Self.shouldTryNextModel(for: error), !isLastModel else { throw error }
                lastError = error
            }
        }
        throw lastError ?? ServiceError.emptyResponse
    }

    /// One model's attempts: retries a momentary overload/network blip with exponential backoff
    /// before giving up on this model.
    private func generateWithRetry(payload: Data, apiKey: String, model: String) async throws -> [Part] {
        var attempt = 1
        while true {
            do {
                return try await performGenerate(payload: payload, apiKey: apiKey, model: model)
            } catch {
                guard attempt < Self.maxAttemptsPerModel, Self.isRetryable(error) else { throw error }
                // ~0.6s pause before the single retry — long enough for a brief blip, short enough
                // not to stall the fail-over. Task.sleep honours cancellation, so a cancelled turn
                // stops here.
                let seconds = 0.6 * pow(2.0, Double(attempt - 1))
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                attempt += 1
            }
        }
    }

    /// One `generateContent` round trip against `model`, with no retry.
    private func performGenerate(payload: Data, apiKey: String, model: String) async throws -> [Part] {
        var request = URLRequest(url: Self.endpoint(for: model))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Header (not the ?key= query param) so the key never lands in a URL/log.
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 60
        request.httpBody = payload

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
            throw ServiceError.server(status: httpResponse.statusCode, message: envelope?.error?.message)
        }

        let message = try JSONDecoder().decode(GenerateResponse.self, from: data)
        // No candidate usually means the prompt was blocked by a safety filter.
        guard let candidate = message.candidates?.first else {
            if message.promptFeedback?.blockReason != nil { throw ServiceError.blocked }
            throw ServiceError.emptyResponse
        }
        if let reason = candidate.finishReason, reason != "STOP", reason != "MAX_TOKENS" {
            throw ServiceError.blocked
        }
        guard let parts = candidate.content?.parts, !parts.isEmpty else { throw ServiceError.emptyResponse }
        return parts
    }

    /// Whether an error from `performGenerate` is a transient one worth retrying: a retryable HTTP
    /// status, or a momentary network drop/timeout. A genuine "no internet" isn't retried — the
    /// feature already falls back to the on-device numbers in that case, so retrying only delays it.
    private static func isRetryable(_ error: Error) -> Bool {
        if let service = error as? ServiceError, case .server(let status, _) = service {
            return retryableStatuses.contains(status)
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed:
                return true
            default:
                return false
            }
        }
        return false
    }

    /// Whether to move on to the next model in the chain: the transient/overload cases *plus* a 404,
    /// which means this specific model isn't available to the project (e.g. a model retired for new
    /// users) — a different model in the chain may still work. This is broader than `isRetryable`,
    /// which only governs retrying the *same* model (where a 404 would just repeat).
    private static func shouldTryNextModel(for error: Error) -> Bool {
        if isRetryable(error) { return true }
        if let service = error as? ServiceError, case .server(let status, _) = service {
            return status == 404
        }
        return false
    }

    /// Text-only convenience over `generateParts` for the structured-output path.
    private func generateText(body: [String: Any], apiKey: String) async throws -> String {
        let texts = try await generateParts(body: body, apiKey: apiKey).compactMap(\.text)
        guard !texts.isEmpty else { throw ServiceError.emptyResponse }
        return texts.joined()
    }

    // MARK: - Request pieces

    /// The wire payload: category names, per-month category totals, average monthly income, the
    /// monthly-equivalent recurring total, and recent transaction lines (date, amount, category,
    /// merchant) — never account names or balances.
    private static func prompt(for summary: BudgetSuggestionService.Summary) -> String {
        let categoryLines = summary.stats.map { stat in
            let months = stat.monthlyTotals.map { "\($0)" }.joined(separator: ", ")
            return "- \(stat.category.name): monthly spend over the last \(summary.months) months (oldest first): [\(months)]; average \(stat.average)"
        }
        .joined(separator: "\n")

        return """
        You are helping someone build next month's zero-based personal budget from their actual \
        spending history. All amounts are Canadian dollars.

        Average monthly income: \(summary.averageMonthlyIncome)
        Monthly recurring subscriptions/bills (already included inside category spend): \(summary.monthlyRecurringCommitments)

        Spending by category:
        \(categoryLines)

        Recent transactions (date | amount, negative = money out | category | merchant):
        \(summary.recentTransactions.joined(separator: "\n"))

        Propose a monthly budget amount for every category listed (use the exact category names \
        given). Base each amount on the history: near the average for stable categories, closer \
        to recent months when the trend is clearly up or down, and slightly below average where \
        the transactions show obvious room to trim discretionary spending. Use sensible round \
        numbers. For each category give a one-sentence rationale grounded in its numbers.

        In `savings`, propose a monthly amount to set aside, in proportion to the gap between the \
        average monthly income and the spending you are budgeting: when income comfortably \
        exceeds spending, direct most of that surplus to savings; when the budget is tight, keep \
        it small or zero. Category budgets plus savings must total at or below the average \
        monthly income. In `summary`, give a 2-3 sentence plain-English overview of the plan, the \
        savings rate, and the single biggest saving opportunity.
        """
    }

    /// Gemini's schema dialect is an OpenAPI 3.0 subset: type names are UPPERCASE and
    /// `additionalProperties` isn't supported, so it's omitted here.
    private static let outputSchema: [String: Any] = [
        "type": "OBJECT",
        "properties": [
            "categories": [
                "type": "ARRAY",
                "items": [
                    "type": "OBJECT",
                    "properties": [
                        "name": ["type": "STRING"],
                        "amount": ["type": "NUMBER"],
                        "rationale": ["type": "STRING"]
                    ] as [String: Any],
                    "required": ["name", "amount", "rationale"],
                    "propertyOrdering": ["name", "amount", "rationale"]
                ] as [String: Any]
            ] as [String: Any],
            "savings": [
                "type": "OBJECT",
                "properties": [
                    "amount": ["type": "NUMBER"],
                    "rationale": ["type": "STRING"]
                ] as [String: Any],
                "required": ["amount", "rationale"],
                "propertyOrdering": ["amount", "rationale"]
            ] as [String: Any],
            "summary": ["type": "STRING"]
        ] as [String: Any],
        "required": ["categories", "savings", "summary"],
        "propertyOrdering": ["categories", "savings", "summary"]
    ]

    // MARK: - JSON helpers

    private static func jsonObject(from json: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
    }

    private static func json(from args: FunctionCallPayload.Args) -> String {
        var object: [String: Any] = [:]
        if let categories = args.categories {
            object["categories"] = categories.compactMap { item -> [String: Any]? in
                guard let name = item.name, let amount = item.amount else { return nil }
                return ["name": name, "amount": amount]
            }
        }
        if let savings = args.savingsAmount { object["savingsAmount"] = savings }
        if let month = args.month { object["month"] = month }
        if let startMonth = args.startMonth { object["startMonth"] = startMonth }
        if let endMonth = args.endMonth { object["endMonth"] = endMonth }
        if let summary = args.summary { object["summary"] = summary }
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Response envelope

    private struct GenerateResponse: Decodable {
        let candidates: [Candidate]?
        let promptFeedback: PromptFeedback?
    }

    private struct Candidate: Decodable {
        let content: Content?
        let finishReason: String?
    }

    private struct Content: Decodable {
        let parts: [Part]?
    }

    private struct Part: Decodable {
        let text: String?
        let functionCall: FunctionCallPayload?
    }

    /// Only one tool exists, so the arguments decode straight into its shape. Every field is
    /// optional so a malformed call degrades to "no plan" instead of failing the whole response.
    private struct FunctionCallPayload: Decodable {
        struct Args: Decodable {
            struct PlanCategory: Decodable {
                let name: String?
                let amount: Double?
            }
            let categories: [PlanCategory]?
            let savingsAmount: Double?
            let month: String?
            let startMonth: String?
            let endMonth: String?
            let summary: String?
        }
        let name: String
        let args: Args?
    }

    private struct PromptFeedback: Decodable {
        let blockReason: String?
    }

    private struct ErrorEnvelope: Decodable {
        struct APIError: Decodable {
            let message: String?
        }
        let error: APIError?
    }
}
