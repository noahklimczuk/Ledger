import SwiftData
import SwiftUI

@main
struct LedgerApp: App {
    @State private var lockService = AppLockService()
    @State private var showSplash = true
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
                if showSplash {
                    SplashView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .tint(.accentColor)
            .animation(.default, value: lockService.isUnlocked)
            .animation(.easeOut(duration: 0.4), value: showSplash)
            .task {
                try? await Task.sleep(nanoseconds: 1_300_000_000)
                showSplash = false
            }
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                lockService.lock()
            }
        }
    }
}
