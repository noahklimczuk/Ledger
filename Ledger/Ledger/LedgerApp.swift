import SwiftData
import SwiftUI

@main
struct LedgerApp: App {
    @State private var lockService = AppLockService()
    @Environment(\.scenePhase) private var scenePhase

    private var sharedModelContainer: ModelContainer = {
        let schema = Schema(LedgerSchema.models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootTabView()
                if !lockService.isUnlocked {
                    AppLockView(lockService: lockService)
                        .transition(.opacity)
                }
            }
            .animation(.default, value: lockService.isUnlocked)
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                lockService.lock()
            }
        }
    }
}
