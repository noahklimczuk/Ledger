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

    /// Models tried in order, best-first. Gemini 3.5 Pro leads for the smartest answers; if the key
    /// can't reach it (not on the tier → 403, or absent → 404) or it's saturated (503/429), the chain
    /// falls through to 3.5 Flash — the most capable Flash model — and then the lighter, less-
    /// contended 3.1 Flash-Lite, so the request still completes on a free-tier key. All are current
    /// 3.x models — the 2.5 family is now 404 "no longer available to new users" on freshly created
    /// projects, so it must NOT be in this chain. All support the structured (schema-constrained)
    /// output and function calling this feature needs.
    private static let modelFallbackChain = ["gemini-3.5-pro", "gemini-3.5-flash", "gemini-3.1-flash-lite"]
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
        /// `thoughtSignature` is Gemini's opaque base64 reasoning token for this turn. Gemini 3.x
        /// requires it to be echoed back on the same part in later requests, or the next tool
        /// round-trip fails with a 400 ("Function call is missing a thought_signature").
        case model(text: String?, functionCall: FunctionCallEcho?, thoughtSignature: String?)
        case functionResponse(name: String, responseJSON: String)
    }

    /// A model-issued function call as it gets echoed back into conversation history.
    struct FunctionCallEcho: Sendable {
        let name: String
        let argsJSON: String
    }

    /// A budget the model asked us to delete via the `delete_budget` tool.
    struct BudgetDeletion: Sendable {
        let categoryName: String?
        let month: String?
        let summary: String?
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

    /// A transaction the model asked us to create via the `create_transaction` tool.
    struct TransactionPlan: Sendable {
        enum Direction: String, Sendable { case expense, income }

        let merchant: String
        let amount: Decimal
        let direction: Direction
        let date: String?
        let accountName: String?
        let categoryName: String?
        let notes: String?
        let isReviewed: Bool
        let summary: String?
    }

    /// An account the model asked us to create via the `create_account` tool.
    struct AccountPlan: Sendable {
        let name: String
        let accountTypeRaw: String
        let institutionName: String?
        let startingBalance: Decimal
        let summary: String?
    }

    /// A bill reminder the model asked us to create via the `create_bill` tool.
    struct BillPlan: Sendable {
        let name: String
        let amount: Decimal
        let dueDate: String?
        let cadence: RecurrenceCadence?
        let notifyDaysBefore: Int
        let summary: String?
    }

    /// A savings goal the model asked us to create via the `create_goal` tool.
    struct GoalPlan: Sendable {
        let name: String
        let sfSymbolName: String
        let colorHex: String
        let targetAmount: Decimal
        let currentAmount: Decimal
        let targetDate: String?
        let accountName: String?
        let summary: String?
    }

    /// A transaction the model asked us to delete via the `delete_transaction` tool.
    struct TransactionDeletion: Sendable {
        let merchant: String
        let amount: Decimal?
        let date: String?
        let summary: String?
    }

    /// An account the model asked us to delete via the `delete_account` tool.
    struct AccountDeletion: Sendable {
        let name: String
        let summary: String?
    }

    /// A bill reminder the model asked us to delete via the `delete_bill` tool.
    struct BillDeletion: Sendable {
        let name: String
        let summary: String?
    }

    /// A savings goal the model asked us to delete via the `delete_goal` tool.
    struct GoalDeletion: Sendable {
        let name: String
        let summary: String?
    }

    /// A transaction the model asked us to update via the `update_transaction` tool.
    struct TransactionUpdate: Sendable {
        let merchant: String
        let amount: Decimal?
        let date: String?
        let newMerchant: String?
        let newAmount: Decimal?
        let newDate: String?
        let newCategoryName: String?
        let newAccountName: String?
        let newNotes: String?
        let newIsReviewed: Bool?
        let summary: String?
    }

    /// An account the model asked us to update via the `update_account` tool.
    struct AccountUpdate: Sendable {
        let name: String
        let newName: String?
        let newAccountTypeRaw: String?
        let newInstitutionName: String?
        let newStartingBalance: Decimal?
        let summary: String?
    }

    /// A bill reminder the model asked us to update via the `update_bill` tool.
    struct BillUpdate: Sendable {
        let name: String
        let newName: String?
        let newAmount: Decimal?
        let newDueDate: String?
        let newCadence: RecurrenceCadence?
        let newNotifyDaysBefore: Int?
        let summary: String?
    }

    /// A savings goal the model asked us to update via the `update_goal` tool.
    struct GoalUpdate: Sendable {
        let name: String
        let newName: String?
        let newTargetAmount: Decimal?
        let newCurrentAmount: Decimal?
        let newTargetDate: String?
        let newAccountName: String?
        let newSFSymbolName: String?
        let newColorHex: String?
        let summary: String?
    }

    /// What one advisor round produced: text to show, and/or a budget plan to apply.
    struct AdvisorReply: Sendable {
        let text: String
        let budgetPlan: BudgetPlan?
        /// The call's raw arguments, echoed back into history alongside our function response.
        let budgetPlanArgsJSON: String?
        /// A budget deletion the model asked us to apply, if any.
        let deletePlan: BudgetDeletion?
        let deletePlanArgsJSON: String?
        /// A transaction the model asked us to record, if any.
        let transactionPlan: TransactionPlan?
        let transactionArgsJSON: String?
        /// An account the model asked us to add, if any.
        let accountPlan: AccountPlan?
        let accountArgsJSON: String?
        /// A bill the model asked us to add, if any.
        let billPlan: BillPlan?
        let billArgsJSON: String?
        /// A goal the model asked us to add, if any.
        let goalPlan: GoalPlan?
        let goalArgsJSON: String?
        /// A transaction the model asked us to delete, if any.
        let transactionDeletion: TransactionDeletion?
        let transactionDeletionArgsJSON: String?
        /// An account the model asked us to delete, if any.
        let accountDeletion: AccountDeletion?
        let accountDeletionArgsJSON: String?
        /// A bill the model asked us to delete, if any.
        let billDeletion: BillDeletion?
        let billDeletionArgsJSON: String?
        /// A goal the model asked us to delete, if any.
        let goalDeletion: GoalDeletion?
        let goalDeletionArgsJSON: String?
        /// A transaction the model asked us to update, if any.
        let transactionUpdate: TransactionUpdate?
        let transactionUpdateArgsJSON: String?
        /// An account the model asked us to update, if any.
        let accountUpdate: AccountUpdate?
        let accountUpdateArgsJSON: String?
        /// A bill the model asked us to update, if any.
        let billUpdate: BillUpdate?
        let billUpdateArgsJSON: String?
        /// A goal the model asked us to update, if any.
        let goalUpdate: GoalUpdate?
        let goalUpdateArgsJSON: String?
        /// Gemini's reasoning token for this reply (from the function-call part when present, else the
        /// text part). Must be echoed back on the same part in the next request; see `ChatTurn.model`.
        let thoughtSignature: String?
    }

    /// Freeform advisor reply for the multi-turn financial-advisor chat. `system` carries the
    /// advisor persona plus the financial snapshot (budget totals and recent transactions);
    /// `history` is the running exchange, oldest first, ending with the user's latest question or
    /// our latest function response. The model may answer with text or call any of the available
    /// budget/transaction/account/bill/goal creation or deletion tools.
    func advise(system: String, history: [ChatTurn], apiKey: String) async throws -> AdvisorReply {
        var contents: [[String: Any]] = []
        for turn in history {
            switch turn {
            case .user(let text):
                contents.append(["role": "user", "parts": [["text": text]]])
            case .model(let text, let functionCall, let thoughtSignature):
                var parts: [[String: Any]] = []
                if let text {
                    var part: [String: Any] = ["text": text]
                    // With no function call, the signature (if any) rides on the text part.
                    if functionCall == nil, let thoughtSignature { part["thoughtSignature"] = thoughtSignature }
                    parts.append(part)
                }
                if let functionCall {
                    let call: [String: Any] = ["name": functionCall.name, "args": Self.jsonObject(from: functionCall.argsJSON)]
                    var part: [String: Any] = ["functionCall": call]
                    // Gemini requires its reasoning token echoed back on the function-call part.
                    if let thoughtSignature { part["thoughtSignature"] = thoughtSignature }
                    parts.append(part)
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
            "tools": [["functionDeclarations": [
                Self.createBudgetDeclaration,
                Self.deleteBudgetDeclaration,
                Self.createTransactionDeclaration,
                Self.updateTransactionDeclaration,
                Self.createAccountDeclaration,
                Self.updateAccountDeclaration,
                Self.createBillDeclaration,
                Self.updateBillDeclaration,
                Self.createGoalDeclaration,
                Self.updateGoalDeclaration,
                Self.deleteTransactionDeclaration,
                Self.deleteAccountDeclaration,
                Self.deleteBillDeclaration,
                Self.deleteGoalDeclaration
            ]]]
        ]
        let parts = try await generateParts(body: body, apiKey: apiKey)

        let text = parts.compactMap(\.text).joined()
        var plan: BudgetPlan?
        var planArgsJSON: String?
        var deletePlan: BudgetDeletion?
        var deleteArgsJSON: String?
        // Gemini 3.x attaches a reasoning token per part; capture it so it can be echoed back on the
        // next request. Prefer the function-call part's token (the one the API enforces), else the
        // last part that carries one.
        let toolNames: Set<String> = [
            Self.createBudgetToolName,
            Self.deleteBudgetToolName,
            Self.createTransactionToolName,
            Self.updateTransactionToolName,
            Self.createAccountToolName,
            Self.updateAccountToolName,
            Self.createBillToolName,
            Self.updateBillToolName,
            Self.createGoalToolName,
            Self.updateGoalToolName,
            Self.deleteTransactionToolName,
            Self.deleteAccountToolName,
            Self.deleteBillToolName,
            Self.deleteGoalToolName
        ]
        let callPart = parts.first { toolNames.contains($0.functionCall?.name ?? "") }
        let thoughtSignature = callPart?.thoughtSignature ?? parts.compactMap(\.thoughtSignature).last
        var transactionPlan: TransactionPlan?
        var transactionArgsJSON: String?
        var accountPlan: AccountPlan?
        var accountArgsJSON: String?
        var billPlan: BillPlan?
        var billArgsJSON: String?
        var goalPlan: GoalPlan?
        var goalArgsJSON: String?
        var transactionDeletion: TransactionDeletion?
        var transactionDeletionArgsJSON: String?
        var accountDeletion: AccountDeletion?
        var accountDeletionArgsJSON: String?
        var billDeletion: BillDeletion?
        var billDeletionArgsJSON: String?
        var goalDeletion: GoalDeletion?
        var goalDeletionArgsJSON: String?
        var transactionUpdate: TransactionUpdate?
        var transactionUpdateArgsJSON: String?
        var accountUpdate: AccountUpdate?
        var accountUpdateArgsJSON: String?
        var billUpdate: BillUpdate?
        var billUpdateArgsJSON: String?
        var goalUpdate: GoalUpdate?
        var goalUpdateArgsJSON: String?
        if let call = callPart?.functionCall, let args = call.args {
            switch call.name {
            case Self.createBudgetToolName:
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
                    planArgsJSON = Self.json(from: args)
                }
            case Self.deleteBudgetToolName:
                deletePlan = BudgetDeletion(
                    categoryName: args.categoryName,
                    month: args.month,
                    summary: args.summary
                )
                deleteArgsJSON = Self.json(from: args)
            case Self.createTransactionToolName:
                if let merchant = args.merchant, let amount = args.amount, amount > 0 {
                    let direction = TransactionPlan.Direction(rawValue: (args.direction ?? "expense").lowercased()) ?? .expense
                    transactionPlan = TransactionPlan(
                        merchant: merchant,
                        amount: Decimal(amount),
                        direction: direction,
                        date: args.date,
                        accountName: args.accountName,
                        categoryName: args.categoryName,
                        notes: args.notes,
                        isReviewed: args.isReviewed ?? true,
                        summary: args.summary
                    )
                    transactionArgsJSON = Self.json(from: args)
                }
            case Self.createAccountToolName:
                if let name = args.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let typeRaw = args.accountType?.lowercased() {
                    accountPlan = AccountPlan(
                        name: name,
                        accountTypeRaw: typeRaw,
                        institutionName: args.institutionName?.trimmingCharacters(in: .whitespacesAndNewlines),
                        startingBalance: Decimal(args.startingBalance ?? 0),
                        summary: args.summary
                    )
                    accountArgsJSON = Self.json(from: args)
                }
            case Self.createBillToolName:
                if let name = args.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let amount = args.amount, amount > 0 {
                    let cadence = args.cadence.flatMap { RecurrenceCadence(rawValue: $0.lowercased()) }
                    billPlan = BillPlan(
                        name: name,
                        amount: Decimal(amount),
                        dueDate: args.dueDate,
                        cadence: cadence,
                        notifyDaysBefore: max(args.notifyDaysBefore ?? 1, 0),
                        summary: args.summary
                    )
                    billArgsJSON = Self.json(from: args)
                }
            case Self.createGoalToolName:
                if let name = args.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let targetAmount = args.targetAmount, targetAmount > 0 {
                    goalPlan = GoalPlan(
                        name: name,
                        sfSymbolName: args.sfSymbolName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "target",
                        colorHex: args.colorHex?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "#34C759",
                        targetAmount: Decimal(targetAmount),
                        currentAmount: Decimal(max(args.currentAmount ?? 0, 0)),
                        targetDate: args.targetDate,
                        accountName: args.accountName?.trimmingCharacters(in: .whitespacesAndNewlines),
                        summary: args.summary
                    )
                    goalArgsJSON = Self.json(from: args)
                }
            case Self.deleteTransactionToolName:
                if let merchant = args.merchant, !merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    transactionDeletion = TransactionDeletion(
                        merchant: merchant,
                        amount: args.amount.map { Decimal($0) },
                        date: args.date,
                        summary: args.summary
                    )
                    transactionDeletionArgsJSON = Self.json(from: args)
                }
            case Self.deleteAccountToolName:
                if let name = args.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    accountDeletion = AccountDeletion(name: name, summary: args.summary)
                    accountDeletionArgsJSON = Self.json(from: args)
                }
            case Self.deleteBillToolName:
                if let name = args.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    billDeletion = BillDeletion(name: name, summary: args.summary)
                    billDeletionArgsJSON = Self.json(from: args)
                }
            case Self.deleteGoalToolName:
                if let name = args.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    goalDeletion = GoalDeletion(name: name, summary: args.summary)
                    goalDeletionArgsJSON = Self.json(from: args)
                }
            case Self.updateTransactionToolName:
                if let merchant = args.merchant, !merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    transactionUpdate = TransactionUpdate(
                        merchant: merchant,
                        amount: args.amount.map { Decimal($0) },
                        date: args.date,
                        newMerchant: args.newMerchant?.trimmingCharacters(in: .whitespacesAndNewlines),
                        newAmount: args.newAmount.map { Decimal($0) },
                        newDate: args.newDate,
                        newCategoryName: args.newCategoryName?.trimmingCharacters(in: .whitespacesAndNewlines),
                        newAccountName: args.newAccountName?.trimmingCharacters(in: .whitespacesAndNewlines),
                        newNotes: args.newNotes,
                        newIsReviewed: args.newIsReviewed,
                        summary: args.summary
                    )
                    transactionUpdateArgsJSON = Self.json(from: args)
                }
            case Self.updateAccountToolName:
                if let name = args.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    accountUpdate = AccountUpdate(
                        name: name,
                        newName: args.newName?.trimmingCharacters(in: .whitespacesAndNewlines),
                        newAccountTypeRaw: args.newAccountType?.lowercased(),
                        newInstitutionName: args.newInstitutionName?.trimmingCharacters(in: .whitespacesAndNewlines),
                        newStartingBalance: args.newStartingBalance.map { Decimal($0) },
                        summary: args.summary
                    )
                    accountUpdateArgsJSON = Self.json(from: args)
                }
            case Self.updateBillToolName:
                if let name = args.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    billUpdate = BillUpdate(
                        name: name,
                        newName: args.newName?.trimmingCharacters(in: .whitespacesAndNewlines),
                        newAmount: args.newAmount.map { Decimal($0) },
                        newDueDate: args.newDueDate,
                        newCadence: args.newCadence.flatMap { RecurrenceCadence(rawValue: $0.lowercased()) },
                        newNotifyDaysBefore: args.newNotifyDaysBefore,
                        summary: args.summary
                    )
                    billUpdateArgsJSON = Self.json(from: args)
                }
            case Self.updateGoalToolName:
                if let name = args.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    goalUpdate = GoalUpdate(
                        name: name,
                        newName: args.newName?.trimmingCharacters(in: .whitespacesAndNewlines),
                        newTargetAmount: args.newTargetAmount.map { Decimal($0) },
                        newCurrentAmount: args.newCurrentAmount.map { Decimal($0) },
                        newTargetDate: args.newTargetDate,
                        newAccountName: args.newAccountName?.trimmingCharacters(in: .whitespacesAndNewlines),
                        newSFSymbolName: args.newSFSymbolName?.trimmingCharacters(in: .whitespacesAndNewlines),
                        newColorHex: args.newColorHex?.trimmingCharacters(in: .whitespacesAndNewlines),
                        summary: args.summary
                    )
                    goalUpdateArgsJSON = Self.json(from: args)
                }
            default:
                break
            }
        }

        guard plan != nil || deletePlan != nil || transactionPlan != nil || accountPlan != nil || billPlan != nil || goalPlan != nil || transactionDeletion != nil || accountDeletion != nil || billDeletion != nil || goalDeletion != nil || transactionUpdate != nil || accountUpdate != nil || billUpdate != nil || goalUpdate != nil || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServiceError.emptyResponse
        }
        return AdvisorReply(
            text: text,
            budgetPlan: plan,
            budgetPlanArgsJSON: planArgsJSON,
            deletePlan: deletePlan,
            deletePlanArgsJSON: deleteArgsJSON,
            transactionPlan: transactionPlan,
            transactionArgsJSON: transactionArgsJSON,
            accountPlan: accountPlan,
            accountArgsJSON: accountArgsJSON,
            billPlan: billPlan,
            billArgsJSON: billArgsJSON,
            goalPlan: goalPlan,
            goalArgsJSON: goalArgsJSON,
            transactionDeletion: transactionDeletion,
            transactionDeletionArgsJSON: transactionDeletionArgsJSON,
            accountDeletion: accountDeletion,
            accountDeletionArgsJSON: accountDeletionArgsJSON,
            billDeletion: billDeletion,
            billDeletionArgsJSON: billDeletionArgsJSON,
            goalDeletion: goalDeletion,
            goalDeletionArgsJSON: goalDeletionArgsJSON,
            transactionUpdate: transactionUpdate,
            transactionUpdateArgsJSON: transactionUpdateArgsJSON,
            accountUpdate: accountUpdate,
            accountUpdateArgsJSON: accountUpdateArgsJSON,
            billUpdate: billUpdate,
            billUpdateArgsJSON: billUpdateArgsJSON,
            goalUpdate: goalUpdate,
            goalUpdateArgsJSON: goalUpdateArgsJSON,
            thoughtSignature: thoughtSignature
        )
    }

    static let createBudgetToolName = "create_budget"
    static let deleteBudgetToolName = "delete_budget"
    static let createTransactionToolName = "create_transaction"
    static let createAccountToolName = "create_account"
    static let createBillToolName = "create_bill"
    static let createGoalToolName = "create_goal"
    static let updateTransactionToolName = "update_transaction"
    static let updateAccountToolName = "update_account"
    static let updateBillToolName = "update_bill"
    static let updateGoalToolName = "update_goal"
    static let deleteTransactionToolName = "delete_transaction"
    static let deleteAccountToolName = "delete_account"
    static let deleteBillToolName = "delete_bill"
    static let deleteGoalToolName = "delete_goal"

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

    /// The tool the advisor can call to delete the user's monthly budgets. Omit `categoryName` to
    /// delete the entire month's plan; provide it (matching an exact expense category name) to
    /// delete that category's budget only.
    private static let deleteBudgetDeclaration: [String: Any] = [
        "name": deleteBudgetToolName,
        "description": "Delete the user's category budgets for a specific month. Call this only when the user asks to delete, remove, or clear a budget or the whole month's budget plan. Omit categoryName to wipe the entire month; include it to delete only that category's budget. The month defaults to the conversation's open month if omitted.",
        "parameters": [
            "type": "OBJECT",
            "properties": [
                "month": [
                    "type": "STRING",
                    "description": "Which single month to delete budgets for, as \"YYYY-MM\". Omit to use the open month."
                ],
                "categoryName": [
                    "type": "STRING",
                    "description": "Exact name of one of the user's expense categories to remove the budget for. Omit to delete the whole month's budgets."
                ],
                "summary": [
                    "type": "STRING",
                    "description": "One sentence confirming what was deleted."
                ]
            ] as [String: Any]
        ] as [String: Any]
    ]

    /// The tool the advisor can call to record a transaction. Call this when the user says something
    /// like "I spent $12 at Starbucks", "add my paycheck", or "record rent for the first". The model
    /// must resolve the date to "YYYY-MM-DD" and pick an account and category from the lists
    /// provided in the system prompt.
    private static let createTransactionDeclaration: [String: Any] = [
        "name": createTransactionToolName,
        "description": "Record a single transaction in Ledger. Call this when the user asks to add, record, or log spending/income (e.g. \"I spent $12 at Starbucks\", \"add my paycheck\", \"record rent\"). Resolve relative dates like \"today\", \"yesterday\", or \"last Friday\" into the `date` field as \"YYYY-MM-DD\". Use the exact account and category names from the lists in the system prompt; if no match is close, leave categoryName blank and the user can categorize later.",
        "parameters": [
            "type": "OBJECT",
            "properties": [
                "merchant": [
                    "type": "STRING",
                    "description": "Short merchant or description, e.g. \"Starbucks\", \"Paycheque\", \"Rent\"."
                ],
                "amount": [
                    "type": "NUMBER",
                    "description": "Positive amount of the transaction."
                ],
                "direction": [
                    "type": "STRING",
                    "description": "expense for money out, income for money in. Defaults to expense if not sure."
                ],
                "date": [
                    "type": "STRING",
                    "description": "Date as \"YYYY-MM-DD\". Defaults to today if omitted."
                ],
                "accountName": [
                    "type": "STRING",
                    "description": "Exact name of one of the user's accounts."
                ],
                "categoryName": [
                    "type": "STRING",
                    "description": "Exact name of one of the user's categories, or blank if unsure."
                ],
                "notes": [
                    "type": "STRING",
                    "description": "Optional extra details."
                ],
                "isReviewed": [
                    "type": "BOOLEAN",
                    "description": "Whether the transaction should be marked as already reviewed. Defaults to true."
                ],
                "summary": [
                    "type": "STRING",
                    "description": "One sentence confirming what was recorded."
                ]
            ] as [String: Any],
            "required": ["merchant", "amount"]
        ] as [String: Any]
    ]

    /// The tool the advisor can call to add a manual account.
    private static let createAccountDeclaration: [String: Any] = [
        "name": createAccountToolName,
        "description": "Add a manual account to Ledger. Call this when the user asks to add, create, or track an account (e.g. \"add a savings account\", \"I opened a new chequing account\").",
        "parameters": [
            "type": "OBJECT",
            "properties": [
                "name": [
                    "type": "STRING",
                    "description": "Display name for the account, e.g. \"Scotiabank Chequing\"."
                ],
                "accountType": [
                    "type": "STRING",
                    "description": "One of: chequing, savings, credit, investment. Defaults to chequing if unknown."
                ],
                "institutionName": [
                    "type": "STRING",
                    "description": "Optional bank or institution name."
                ],
                "startingBalance": [
                    "type": "NUMBER",
                    "description": "Current balance to start tracking from. Positive for assets, negative for credit card debt. Defaults to 0."
                ],
                "summary": [
                    "type": "STRING",
                    "description": "One sentence confirming what was added."
                ]
            ] as [String: Any],
            "required": ["name", "accountType"]
        ] as [String: Any]
    ]

    /// The tool the advisor can call to add a bill or subscription reminder.
    private static let createBillDeclaration: [String: Any] = [
        "name": createBillToolName,
        "description": "Add a bill or subscription reminder in Ledger. Call this when the user asks to add, remind, or track a bill (e.g. \"remind me about rent on the 1st\", \"add a $15 monthly Netflix subscription\").",
        "parameters": [
            "type": "OBJECT",
            "properties": [
                "name": [
                    "type": "STRING",
                    "description": "Name of the bill or subscription, e.g. \"Rent\", \"Netflix\"."
                ],
                "amount": [
                    "type": "NUMBER",
                    "description": "Positive amount due."
                ],
                "dueDate": [
                    "type": "STRING",
                    "description": "Next due date as \"YYYY-MM-DD\". Resolve relative dates like \"today\", \"tomorrow\", or \"the 15th\" against today's date."
                ],
                "cadence": [
                    "type": "STRING",
                    "description": "How often the bill repeats: weekly, biweekly, monthly, quarterly, yearly. Omit for a one-time bill."
                ],
                "notifyDaysBefore": [
                    "type": "INTEGER",
                    "description": "How many days before the due date to send a notification. Defaults to 1."
                ],
                "summary": [
                    "type": "STRING",
                    "description": "One sentence confirming what was added."
                ]
            ] as [String: Any],
            "required": ["name", "amount", "dueDate"]
        ] as [String: Any]
    ]

    /// The tool the advisor can call to add a savings goal.
    private static let createGoalDeclaration: [String: Any] = [
        "name": createGoalToolName,
        "description": "Add a savings goal in Ledger. Call this when the user asks to save toward something (e.g. \"save $5,000 for a vacation\", \"goal for a new laptop $1,200\").",
        "parameters": [
            "type": "OBJECT",
            "properties": [
                "name": [
                    "type": "STRING",
                    "description": "Short name of the goal, e.g. \"Vacation\", \"Emergency Fund\"."
                ],
                "targetAmount": [
                    "type": "NUMBER",
                    "description": "Total amount the user wants to save."
                ],
                "currentAmount": [
                    "type": "NUMBER",
                    "description": "Amount already saved toward the goal. Defaults to 0."
                ],
                "targetDate": [
                    "type": "STRING",
                    "description": "Target completion date as \"YYYY-MM-DD\", optional."
                ],
                "accountName": [
                    "type": "STRING",
                    "description": "Exact name of an active account to link, so the account's live balance drives progress. Omit for a manual goal."
                ],
                "sfSymbolName": [
                    "type": "STRING",
                    "description": "An SF Symbols icon name for the goal, e.g. \"airplane\", \"laptopcomputer\". Defaults to \"target\"."
                ],
                "colorHex": [
                    "type": "STRING",
                    "description": "Hex color for the goal, e.g. \"#34C759\". Defaults to \"#34C759\"."
                ],
                "summary": [
                    "type": "STRING",
                    "description": "One sentence confirming what was added."
                ]
            ] as [String: Any],
            "required": ["name", "targetAmount"]
        ] as [String: Any]
    ]

    /// The tool the advisor can call to delete a transaction.
    private static let deleteTransactionDeclaration: [String: Any] = [
        "name": deleteTransactionToolName,
        "description": "Delete a transaction from Ledger. Call this when the user asks to remove, delete, or undo a recorded transaction. Use merchant and optionally amount/date to identify the right one.",
        "parameters": [
            "type": "OBJECT",
            "properties": [
                "merchant": [
                    "type": "STRING",
                    "description": "Merchant or description of the transaction to delete."
                ],
                "amount": [
                    "type": "NUMBER",
                    "description": "Optional exact amount to match."
                ],
                "date": [
                    "type": "STRING",
                    "description": "Optional date as \"YYYY-MM-DD\" to narrow the match."
                ],
                "summary": [
                    "type": "STRING",
                    "description": "One sentence confirming what was deleted."
                ]
            ] as [String: Any],
            "required": ["merchant"]
        ] as [String: Any]
    ]

    /// The tool the advisor can call to delete a manual account.
    private static let deleteAccountDeclaration: [String: Any] = [
        "name": deleteAccountToolName,
        "description": "Delete a manual account from Ledger. Call this when the user asks to remove, delete, or close an account.",
        "parameters": [
            "type": "OBJECT",
            "properties": [
                "name": [
                    "type": "STRING",
                    "description": "Exact name of the account to delete."
                ],
                "summary": [
                    "type": "STRING",
                    "description": "One sentence confirming what was deleted."
                ]
            ] as [String: Any],
            "required": ["name"]
        ] as [String: Any]
    ]

    /// The tool the advisor can call to delete a bill reminder.
    private static let deleteBillDeclaration: [String: Any] = [
        "name": deleteBillToolName,
        "description": "Delete a bill reminder from Ledger. Call this when the user asks to remove or cancel a bill or subscription reminder.",
        "parameters": [
            "type": "OBJECT",
            "properties": [
                "name": [
                    "type": "STRING",
                    "description": "Exact name of the bill to delete."
                ],
                "summary": [
                    "type": "STRING",
                    "description": "One sentence confirming what was deleted."
                ]
            ] as [String: Any],
            "required": ["name"]
        ] as [String: Any]
    ]

    /// The tool the advisor can call to delete a savings goal.
    private static let deleteGoalDeclaration: [String: Any] = [
        "name": deleteGoalToolName,
        "description": "Delete a savings goal from Ledger. Call this when the user asks to remove or abandon a goal.",
        "parameters": [
            "type": "OBJECT",
            "properties": [
                "name": [
                    "type": "STRING",
                    "description": "Exact name of the goal to delete."
                ],
                "summary": [
                    "type": "STRING",
                    "description": "One sentence confirming what was deleted."
                ]
            ] as [String: Any],
            "required": ["name"]
        ] as [String: Any]
    ]

    /// The tool the advisor can call to update a transaction.
    private static let updateTransactionDeclaration: [String: Any] = [
        "name": updateTransactionToolName,
        "description": "Update an existing transaction in Ledger. Call this when the user asks to change, edit, or correct a transaction (e.g. \"change the Starbucks charge to $15\", \"mark my paycheck as reviewed\").",
        "parameters": [
            "type": "OBJECT",
            "properties": [
                "merchant": [
                    "type": "STRING",
                    "description": "Current merchant/description of the transaction to update."
                ],
                "amount": [
                    "type": "NUMBER",
                    "description": "Optional current amount to narrow the match."
                ],
                "date": [
                    "type": "STRING",
                    "description": "Optional current date as \"YYYY-MM-DD\" to narrow the match."
                ],
                "newMerchant": [
                    "type": "STRING",
                    "description": "Optional new merchant/description."
                ],
                "newAmount": [
                    "type": "NUMBER",
                    "description": "Optional new positive amount."
                ],
                "newDate": [
                    "type": "STRING",
                    "description": "Optional new date as \"YYYY-MM-DD\"."
                ],
                "newCategoryName": [
                    "type": "STRING",
                    "description": "Optional exact category name to reassign the transaction to."
                ],
                "newAccountName": [
                    "type": "STRING",
                    "description": "Optional exact account name to move the transaction to."
                ],
                "newNotes": [
                    "type": "STRING",
                    "description": "Optional new notes."
                ],
                "newIsReviewed": [
                    "type": "BOOLEAN",
                    "description": "Optional reviewed flag."
                ],
                "summary": [
                    "type": "STRING",
                    "description": "One sentence confirming what was updated."
                ]
            ] as [String: Any],
            "required": ["merchant"]
        ] as [String: Any]
    ]

    /// The tool the advisor can call to update an account.
    private static let updateAccountDeclaration: [String: Any] = [
        "name": updateAccountToolName,
        "description": "Update a manual account in Ledger. Call this when the user asks to rename, change type, or adjust the starting balance of an account.",
        "parameters": [
            "type": "OBJECT",
            "properties": [
                "name": [
                    "type": "STRING",
                    "description": "Current exact name of the account to update."
                ],
                "newName": [
                    "type": "STRING",
                    "description": "Optional new account name."
                ],
                "newAccountType": [
                    "type": "STRING",
                    "description": "Optional new account type: chequing, savings, credit, investment."
                ],
                "newInstitutionName": [
                    "type": "STRING",
                    "description": "Optional new bank or institution name."
                ],
                "newStartingBalance": [
                    "type": "NUMBER",
                    "description": "Optional new starting balance."
                ],
                "summary": [
                    "type": "STRING",
                    "description": "One sentence confirming what was updated."
                ]
            ] as [String: Any],
            "required": ["name"]
        ] as [String: Any]
    ]

    /// The tool the advisor can call to update a bill reminder.
    private static let updateBillDeclaration: [String: Any] = [
        "name": updateBillToolName,
        "description": "Update a bill reminder in Ledger. Call this when the user asks to change the amount, due date, or cadence of a bill.",
        "parameters": [
            "type": "OBJECT",
            "properties": [
                "name": [
                    "type": "STRING",
                    "description": "Current exact name of the bill to update."
                ],
                "newName": [
                    "type": "STRING",
                    "description": "Optional new bill name."
                ],
                "newAmount": [
                    "type": "NUMBER",
                    "description": "Optional new positive amount."
                ],
                "newDueDate": [
                    "type": "STRING",
                    "description": "Optional new due date as \"YYYY-MM-DD\"."
                ],
                "newCadence": [
                    "type": "STRING",
                    "description": "Optional new cadence: weekly, biweekly, monthly, quarterly, yearly, or omit for one-time."
                ],
                "newNotifyDaysBefore": [
                    "type": "INTEGER",
                    "description": "Optional new notification lead days."
                ],
                "summary": [
                    "type": "STRING",
                    "description": "One sentence confirming what was updated."
                ]
            ] as [String: Any],
            "required": ["name"]
        ] as [String: Any]
    ]

    /// The tool the advisor can call to update a savings goal.
    private static let updateGoalDeclaration: [String: Any] = [
        "name": updateGoalToolName,
        "description": "Update a savings goal in Ledger. Call this when the user asks to change the target, saved amount, linked account, icon, or color of a goal.",
        "parameters": [
            "type": "OBJECT",
            "properties": [
                "name": [
                    "type": "STRING",
                    "description": "Current exact name of the goal to update."
                ],
                "newName": [
                    "type": "STRING",
                    "description": "Optional new goal name."
                ],
                "newTargetAmount": [
                    "type": "NUMBER",
                    "description": "Optional new target amount."
                ],
                "newCurrentAmount": [
                    "type": "NUMBER",
                    "description": "Optional new manually tracked saved amount."
                ],
                "newTargetDate": [
                    "type": "STRING",
                    "description": "Optional new target date as \"YYYY-MM-DD\"."
                ],
                "newAccountName": [
                    "type": "STRING",
                    "description": "Optional exact active account name to link; omit to unlink."
                ],
                "newSFSymbolName": [
                    "type": "STRING",
                    "description": "Optional new SF Symbols icon name."
                ],
                "newColorHex": [
                    "type": "STRING",
                    "description": "Optional new hex color."
                ],
                "summary": [
                    "type": "STRING",
                    "description": "One sentence confirming what was updated."
                ]
            ] as [String: Any],
            "required": ["name"]
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

    /// Whether to move on to the next model in the chain: the transient/overload cases *plus* a 404
    /// (model absent for this project, e.g. retired) or a 403 (model exists but the key's tier can't
    /// use it — e.g. Pro gated to paid). In both cases a lighter model in the chain may still work.
    /// This is broader than `isRetryable`, which only governs retrying the *same* model. On the last
    /// model these still surface, because the caller only advances when it isn't the last one — so a
    /// genuine bad-key 403 on the final model is reported rather than swallowed.
    private static func shouldTryNextModel(for error: Error) -> Bool {
        if isRetryable(error) { return true }
        if let service = error as? ServiceError, case .server(let status, _) = service {
            return status == 404 || status == 403
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
        if let categoryName = args.categoryName { object["categoryName"] = categoryName }
        if let summary = args.summary { object["summary"] = summary }
        if let merchant = args.merchant { object["merchant"] = merchant }
        if let amount = args.amount { object["amount"] = amount }
        if let direction = args.direction { object["direction"] = direction }
        if let date = args.date { object["date"] = date }
        if let accountName = args.accountName { object["accountName"] = accountName }
        if let notes = args.notes { object["notes"] = notes }
        if let isReviewed = args.isReviewed { object["isReviewed"] = isReviewed }
        // create_account / create_bill / create_goal
        if let name = args.name { object["name"] = name }
        if let accountType = args.accountType { object["accountType"] = accountType }
        if let institutionName = args.institutionName { object["institutionName"] = institutionName }
        if let startingBalance = args.startingBalance { object["startingBalance"] = startingBalance }
        if let dueDate = args.dueDate { object["dueDate"] = dueDate }
        if let cadence = args.cadence { object["cadence"] = cadence }
        if let notifyDaysBefore = args.notifyDaysBefore { object["notifyDaysBefore"] = notifyDaysBefore }
        if let sfSymbolName = args.sfSymbolName { object["sfSymbolName"] = sfSymbolName }
        if let colorHex = args.colorHex { object["colorHex"] = colorHex }
        if let targetAmount = args.targetAmount { object["targetAmount"] = targetAmount }
        if let currentAmount = args.currentAmount { object["currentAmount"] = currentAmount }
        if let targetDate = args.targetDate { object["targetDate"] = targetDate }
        // update fields
        if let newMerchant = args.newMerchant { object["newMerchant"] = newMerchant }
        if let newAmount = args.newAmount { object["newAmount"] = newAmount }
        if let newDate = args.newDate { object["newDate"] = newDate }
        if let newCategoryName = args.newCategoryName { object["newCategoryName"] = newCategoryName }
        if let newAccountName = args.newAccountName { object["newAccountName"] = newAccountName }
        if let newNotes = args.newNotes { object["newNotes"] = newNotes }
        if let newIsReviewed = args.newIsReviewed { object["newIsReviewed"] = newIsReviewed }
        if let newName = args.newName { object["newName"] = newName }
        if let newAccountType = args.newAccountType { object["newAccountType"] = newAccountType }
        if let newInstitutionName = args.newInstitutionName { object["newInstitutionName"] = newInstitutionName }
        if let newStartingBalance = args.newStartingBalance { object["newStartingBalance"] = newStartingBalance }
        if let newDueDate = args.newDueDate { object["newDueDate"] = newDueDate }
        if let newCadence = args.newCadence { object["newCadence"] = newCadence }
        if let newNotifyDaysBefore = args.newNotifyDaysBefore { object["newNotifyDaysBefore"] = newNotifyDaysBefore }
        if let newTargetAmount = args.newTargetAmount { object["newTargetAmount"] = newTargetAmount }
        if let newCurrentAmount = args.newCurrentAmount { object["newCurrentAmount"] = newCurrentAmount }
        if let newTargetDate = args.newTargetDate { object["newTargetDate"] = newTargetDate }
        if let newSFSymbolName = args.newSFSymbolName { object["newSFSymbolName"] = newSFSymbolName }
        if let newColorHex = args.newColorHex { object["newColorHex"] = newColorHex }
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
        /// Opaque base64 reasoning token Gemini 3.x attaches to a part; must be round-tripped.
        let thoughtSignature: String?
    }

    /// Arguments for every tool the advisor can call, flattened into one struct. Every field is
    /// optional so a malformed call degrades to "no plan" instead of failing the whole response.
    private struct FunctionCallPayload: Decodable {
        struct Args: Decodable {
            struct PlanCategory: Decodable {
                let name: String?
                let amount: Double?
            }
            // create_budget / delete_budget
            let categories: [PlanCategory]?
            let savingsAmount: Double?
            let month: String?
            let startMonth: String?
            let endMonth: String?
            let categoryName: String?
            let summary: String?
            // create_transaction fields
            let merchant: String?
            let amount: Double?
            let direction: String?
            let date: String?
            let accountName: String?
            let notes: String?
            let isReviewed: Bool?
            // create_account / create_bill / create_goal shared
            let name: String?
            // create_account fields
            let accountType: String?
            let institutionName: String?
            let startingBalance: Double?
            // create_bill fields
            let dueDate: String?
            let cadence: String?
            let notifyDaysBefore: Int?
            // create_goal fields
            let sfSymbolName: String?
            let colorHex: String?
            let targetAmount: Double?
            let currentAmount: Double?
            let targetDate: String?
            // update_transaction fields
            let newMerchant: String?
            let newAmount: Double?
            let newDate: String?
            let newCategoryName: String?
            let newAccountName: String?
            let newNotes: String?
            let newIsReviewed: Bool?
            // update_account fields
            let newName: String?
            let newAccountType: String?
            let newInstitutionName: String?
            let newStartingBalance: Double?
            // update_bill fields
            let newDueDate: String?
            let newCadence: String?
            let newNotifyDaysBefore: Int?
            // update_goal fields
            let newTargetAmount: Double?
            let newCurrentAmount: Double?
            let newTargetDate: String?
            let newSFSymbolName: String?
            let newColorHex: String?
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
