import Foundation

/// Minimal hand-rolled client for Google's Gemini API (no SDK dependency, same approach as
/// `WealthsimpleAPIClient`). Used for exactly one thing: turning the on-device budget summary
/// (aggregated per-category monthly totals — never raw transactions, merchants, accounts, or
/// balances) into suggested amounts with a plain-English rationale.
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

    struct Suggestion: Decodable {
        let categories: [SuggestedCategory]
        /// Plain-English overview of the proposed plan.
        let summary: String
    }

    /// Gemini 2.5 Flash is on the free tier and supports structured (schema-constrained) output.
    private static let model = "gemini-2.5-flash"
    static let apiKeyKeychainKey = "gemini.apiKey"

    private static var endpoint: URL {
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

    /// Asks the model to propose per-category budgets from the aggregated summary. A response
    /// schema (`generationConfig.responseSchema` + `application/json`) guarantees the reply is
    /// valid JSON matching our shape.
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

    /// One turn of an advisor conversation.
    struct ChatTurn: Sendable {
        enum Role: String { case user, model }
        let role: Role
        let text: String
    }

    /// Freeform advisor reply for the multi-turn financial-advisor chat. `system` carries the
    /// advisor persona plus the aggregated (never transaction-level) financial snapshot; `history`
    /// is the running user/model exchange, oldest first, ending with the user's latest question.
    func advise(system: String, history: [ChatTurn], apiKey: String) async throws -> String {
        let contents = history.map { turn in
            ["role": turn.role.rawValue, "parts": [["text": turn.text]]] as [String: Any]
        }
        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": system]]],
            "contents": contents
        ]
        let text = try await generateText(body: body, apiKey: apiKey)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ServiceError.emptyResponse }
        return text
    }

    /// Shared `generateContent` call: POSTs `body`, surfaces server/safety failures, and returns
    /// the concatenated text of the first candidate.
    private func generateText(body: [String: Any], apiKey: String) async throws -> String {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Header (not the ?key= query param) so the key never lands in a URL/log.
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 60
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

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
        let texts = candidate.content?.parts?.compactMap(\.text) ?? []
        guard !texts.isEmpty else { throw ServiceError.emptyResponse }
        return texts.joined()
    }

    // MARK: - Request pieces

    /// Only aggregate numbers go over the wire: category names, per-month category totals,
    /// average monthly income, and the monthly-equivalent recurring total.
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

        Propose a monthly budget amount for every category listed (use the exact category names \
        given). Base each amount on the history: near the average for stable categories, closer \
        to recent months when the trend is clearly up or down, and slightly below average where \
        there is obvious room to trim discretionary spending. Use sensible round numbers. Keep \
        the total at or below the average monthly income when possible. For each category give a \
        one-sentence rationale grounded in its numbers. In `summary`, give a 2-3 sentence \
        plain-English overview of the plan and the single biggest saving opportunity.
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
            "summary": ["type": "STRING"]
        ] as [String: Any],
        "required": ["categories", "summary"],
        "propertyOrdering": ["categories", "summary"]
    ]

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
