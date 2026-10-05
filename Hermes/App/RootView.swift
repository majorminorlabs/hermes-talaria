import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router
    @Environment(HomeStore.self) private var home
    @Environment(ConnectionStore.self) private var connection
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                NavigationStack(path: router.path(for: .home)) {
                    HomeView().routeDestinations()
                }
            }
            .badge(attentionCount)

            Tab("Chat", systemImage: "bubble.left.and.bubble.right", value: AppTab.chat) {
                NavigationStack(path: router.path(for: .chat)) {
                    ConversationListView().routeDestinations()
                }
            }

            Tab("Tasks", systemImage: "checklist", value: AppTab.tasks) {
                NavigationStack(path: router.path(for: .tasks)) {
                    TasksView().routeDestinations()
                }
            }

            Tab("Bots", systemImage: "person.2", value: AppTab.bots) {
                NavigationStack(path: router.path(for: .bots)) {
                    BotsView().routeDestinations()
                }
            }

            Tab("More", systemImage: "ellipsis", value: AppTab.more) {
                NavigationStack(path: router.path(for: .more)) {
                    MoreView().routeDestinations()
                }
            }
        }
        .toastOverlay()
        .preferredColorScheme(preferences.appearance.colorScheme)
        .task { await environment.start() }
        .onChange(of: scenePhase) { oldPhase, phase in
            environment.isInBackground = phase == .background
            // Returning from the background: runs kept going on the host, so
            // reconnect (replaying missed events) if the link dropped.
            let offline = connection.connection == .bridgeOffline || connection.connection == .hermesOffline
            if phase == .active {
                Task {
                    if offline { await connection.reconnect() }
                    await environment.refreshAll()
                }
            }
        }
    }

    private var attentionCount: Int {
        home.attentionItems(connection: connection, preferences: preferences).count
    }
}

#Preview {
    let environment = AppEnvironment.mock(storage: .ephemeral)
    RootView()
        .environment(environment)
        .injectStores(from: environment)
}
