import Foundation

/// Minimal hand-rolled client for the Anthropic Messages API (no SDK dependency, same approach
/// as `PlaidAPIClient`). Used for exactly one thing: turning the on-device budget summary
/// (aggregated per-category monthly totals — never raw transactions, merchants, accounts, or
/// balances) into suggested amounts with a plain-English rationale. The API key comes from the
/// user's own Anthropic console, is stored in the Keychain only, and the feature degrades to the
/// on-device numbers whenever the key or network is missing.
struct AnthropicService: Sendable {
    enum ServiceError: Error, LocalizedError {
        case missingAPIKey
        case invalidResponse
        case server(status: Int, message: String?)
        case refused
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                "Add your Anthropic API key to get AI-tailored suggestions."
            case .invalidResponse:
                "The AI service returned an unexpected response."
            case .server(let status, let message):
                "AI request failed (\(status)): \(message ?? "no details")"
            case .refused:
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

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let model = "claude-opus-4-8"
    static let apiKeyKeychainKey = "anthropic.apiKey"

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

    /// Asks the model to propose per-category budgets from the aggregated summary. Structured
    /// output (`output_config.format`) guarantees the reply is valid JSON matching our schema.
    func suggestBudget(from summary: BudgetSuggestionService.Summary, apiKey: String) async throws -> Suggestion {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 4096,
            "output_config": ["format": Self.outputSchema],
            "messages": [
                ["role": "user", "content": Self.prompt(for: summary)]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
            throw ServiceError.server(status: httpResponse.statusCode, message: envelope?.error?.message)
        }

        let message = try JSONDecoder().decode(MessageResponse.self, from: data)
        if message.stopReason == "refusal" { throw ServiceError.refused }
        guard let text = message.content?.first(where: { $0.type == "text" })?.text,
              let jsonData = text.data(using: .utf8) else {
            throw ServiceError.emptyResponse
        }
        let suggestion = try JSONDecoder().decode(Suggestion.self, from: jsonData)
        guard !suggestion.categories.isEmpty else { throw ServiceError.emptyResponse }
        return suggestion
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

    private static let outputSchema: [String: Any] = [
        "type": "json_schema",
        "schema": [
            "type": "object",
            "properties": [
                "categories": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "name": ["type": "string"],
                            "amount": ["type": "number"],
                            "rationale": ["type": "string"]
                        ],
                        "required": ["name", "amount", "rationale"],
                        "additionalProperties": false
                    ] as [String: Any]
                ] as [String: Any],
                "summary": ["type": "string"]
            ] as [String: Any],
            "required": ["categories", "summary"],
            "additionalProperties": false
        ] as [String: Any]
    ]

    // MARK: - Response envelope

    private struct MessageResponse: Decodable {
        let content: [ContentBlock]?
        let stopReason: String?

        enum CodingKeys: String, CodingKey {
            case content
            case stopReason = "stop_reason"
        }
    }

    private struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }

    private struct ErrorEnvelope: Decodable {
        struct APIError: Decodable {
            let message: String?
        }
        let error: APIError?
    }
}
