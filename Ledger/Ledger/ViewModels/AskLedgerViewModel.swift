import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AskLedgerViewModel {
    private(set) var turns: [AskLedgerTurn] = []
    private(set) var isThinking = false
    private(set) var context = AskLedgerContext()

    var suggestedPrompts: [(icon: String, text: String)] { AskLedgerEngine.suggestedPrompts }
    var hasStarted: Bool { !turns.isEmpty }

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Rebuild the finance snapshot the assistant reasons over.
    func load() {
        context = AskLedgerContext.build(modelContext: modelContext)
    }

    /// Ask a question: append the user's turn, show a brief "thinking" beat, then land the answer.
    func send(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isThinking else { return }

        turns.append(AskLedgerTurn(role: .user, text: question))
        let placeholder = AskLedgerTurn(role: .assistant, isThinking: true)
        turns.append(placeholder)
        isThinking = true

        let response = AskLedgerEngine(context: context).respond(to: question)
        Task { [placeholderID = placeholder.id] in
            // A short, deliberate pause so the answer feels considered rather than instant.
            try? await Task.sleep(nanoseconds: 550_000_000)
            if let index = turns.firstIndex(where: { $0.id == placeholderID }) {
                turns[index].isThinking = false
                turns[index].response = response
            }
            isThinking = false
        }
    }

    func reset() {
        turns.removeAll()
        isThinking = false
    }
}
