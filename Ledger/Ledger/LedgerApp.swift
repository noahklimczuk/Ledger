import SwiftData
import SwiftUI

@main
struct LedgerApp: App {
    @State private var lockService = AppLockService()
    @State private var refreshCoordinator = AppRefreshCoordinator()
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
            .environment(refreshCoordinator)
            .animation(.default, value: lockService.isUnlocked)
            .animation(.easeOut(duration: 0.4), value: showSplash)
            .task {
                // Refresh on cold launch too — `onChange(of: scenePhase)` isn't guaranteed to fire
                // for the initial `.active`. The coordinator's in-flight guard makes an overlap with
                // the scene-phase handler a no-op.
                await refreshCoordinator.refreshOnForeground(container: sharedModelContainer)
            }
            .task {
                try? await Task.sleep(nanoseconds: 1_300_000_000)
                showSplash = false
            }
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                let container = sharedModelContainer
                Task { await refreshCoordinator.refreshOnForeground(container: container) }
            case .background:
                lockService.lock()
            default:
                break
            }
        }
    }
}
