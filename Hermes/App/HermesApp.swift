import SwiftUI

@main
struct HermesApp: App {
    /// Production bridge by default; Simulation and UI tests use isolated mocks.
    /// UI tests get their own sandbox (`-resetState` clears it).
    @State private var environment: AppEnvironment = {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-uiTesting") else {
            return UserDefaults.standard.bool(forKey: "app.backendSimulation") ? .mock(storage: .named("hermes-simulation", reset: false)) : .live()
        }
        return .mock(storage: .named("hermes-uitesting", reset: arguments.contains("-resetState")))
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .injectStores(from: environment)
        }
    }
}

extension View {
    /// Makes each store individually observable from views.
    func injectStores(from environment: AppEnvironment) -> some View {
        self
            .environment(environment.router)
            .environment(environment.toasts)
            .environment(environment.preferences)
            .environment(environment.connection)
            .environment(environment.home)
            .environment(environment.activity)
            .environment(environment.conversations)
            .environment(environment.profiles)
            .environment(environment.tasks)
            .environment(environment.routines)
    }
}
