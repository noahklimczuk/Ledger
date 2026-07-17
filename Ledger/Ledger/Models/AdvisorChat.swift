import Foundation
import SwiftData

/// A saved financial-advisor conversation. The transcript persists across launches so a chat can be
/// reopened and continued; "New Chat" starts a fresh `AdvisorChat` and leaves the old ones in the
/// store, reachable from the history menu.
@Model
final class AdvisorChat {
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    /// The budgeting month the chat was started in — kept for reference; the live system prompt
    /// always reflects the month currently open in the app.
    var month: Date = Date.now
    /// Denormalized label for the history list (the first user message, truncated), so the list
    /// doesn't have to fault every chat's messages just to show a title.
    var title: String = "New Chat"

    @Relationship(deleteRule: .cascade, inverse: \AdvisorChatMessage.chat)
    var messages: [AdvisorChatMessage] = []

    init(month: Date, createdAt: Date = .now) {
        self.month = month
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    /// The transcript in display order.
    var orderedMessages: [AdvisorChatMessage] {
        messages.sorted { $0.sortIndex < $1.sortIndex }
    }
}

/// One persisted line of an `AdvisorChat`. `role` and `kind` are stored as strings so the record
/// stays a plain SwiftData model, decoupled from the view model's enums.
@Model
final class AdvisorChatMessage {
    /// "user" or "assistant".
    var role: String = "assistant"
    /// "text" (a normal chat bubble) or "actionNote" (a note that the advisor applied a budget).
    var kind: String = "text"
    var text: String = ""
    /// Position in the transcript.
    var sortIndex: Int = 0
    var chat: AdvisorChat?

    init(role: String, kind: String, text: String, sortIndex: Int) {
        self.role = role
        self.kind = kind
        self.text = text
        self.sortIndex = sortIndex
    }
}
