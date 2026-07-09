import SwiftUI

struct ErrorStateView: View {
    let message: String
    var retryTitle: String = "Try Again"
    var retry: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label("Something Went Wrong", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            if let retry {
                Button(retryTitle, action: retry)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

#Preview {
    ErrorStateView(message: "Couldn't load your accounts.", retry: {})
}
