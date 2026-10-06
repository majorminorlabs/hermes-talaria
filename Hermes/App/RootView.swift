import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router
    @Environment(HomeStore.self) private var home
    @Environment(ConnectionStore.self) private var connection
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.scenePhase) private var scenePhase

    @State private var liveActivity = HermesLiveActivityController()

    var body: some View {
        @Bindable var router = router
        shell
        .safeAreaInset(edge: .top) {
            if HermesLiveActivityController.demoEnabled {
                HStack {
                    Button(liveActivity.demoRunning ? "Live Activity demo running" : "Run Live Activity demo") { liveActivity.startDemo() }
                        .disabled(liveActivity.demoRunning).accessibilityIdentifier("live-activity-demo")
                    Text(liveActivity.message).font(.caption)
                }.font(.footnote).padding(8).background(.bar)
            }
        }
        .task { if HermesLiveActivityController.demoEnabled { liveActivity.startDemo() } }
        .onChange(of: environment.activity.runs, initial: true) { _, _ in updateLiveActivity() }
        .onChange(of: connection.connection) { _, _ in updateLiveActivity() }
        .overlay(alignment: .bottom) { HeldVoiceOverlay() }
        .sheet(item: $router.askSeed) { AskSheet(seed: $0) }
        .sheet(item: $router.captureSeed) { CaptureSheet(seed: $0) }
        .onOpenURL { router.handle($0) }
        .toastOverlay()
        .preferredColorScheme(preferences.appearance.colorScheme)
        .task { await environment.start() }
        .onChange(of: scenePhase) { oldPhase, phase in
            environment.isInBackground = phase == .background
            // Returning from the background: runs kept going on the host, so
            // reconnect (replaying missed events) if the link dropped.
            let offline = connection.connection == .bridgeOffline || connection.connection == .hermesOffline
            if phase == .active {
                updateLiveActivity()
                Task {
                    if offline { await connection.reconnect() }
                    await environment.refreshAll()
                }
            }
        }
    }

    private func updateLiveActivity() {
        liveActivity.update(runs: environment.activity.runs.values.sorted { $0.id < $1.id }, profiles: environment.profiles, connected: connection.connection.isConnected)
    }

    @ViewBuilder private var shell: some View {
        if #available(iOS 26.0, *) { tabs().tabBarMinimizeBehavior(.onScrollDown) }
        else { tabs() }
    }
    private func tabs() -> some View {
        @Bindable var router = router
        return TabView(selection: $router.selectedTab) {
            Tab("Now", systemImage: "circle.dotted.circle", value: AppTab.now) {
                NavigationStack(path: router.path(for: .now)) { NowView().routeDestinations() }
            }.badge(environment.needsYou.actionableCount)
            Tab("Threads", systemImage: "bubble.left.and.text.bubble.right", value: AppTab.threads) {
                NavigationStack(path: router.path(for: .threads)) { ThreadsView().routeDestinations() }
            }
            Tab("Agents", systemImage: "person.2", value: AppTab.agents) {
                NavigationStack(path: router.path(for: .agents)) { BotsView().routeDestinations() }
            }
        }
    }
}
/// Recording feedback shared by the toolbar and composer.
private struct HeldVoiceOverlay: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router
    var body: some View {
        Group {
            if router.heldVoiceAsk != nil || router.heldVoiceCapture {
                ScrollView {
                    VoiceOverlay(session: environment.voice, send: { _, _ in }, edit: { _ in }, allowAutoSend: false,
                                 targetName: environment.profiles.name(router.heldVoiceAsk?.agentID ?? Profile.defaultID))
                }.fixedSize(horizontal: false, vertical: true).frame(maxHeight: 400)
                    .padding().padding(.bottom, 110)
            }
        }
        .onChange(of: environment.voice.phase) { _, phase in
            guard router.heldVoiceAsk != nil || router.heldVoiceCapture else { return }
            if phase == .review {
                if router.heldVoiceCapture {
                    router.captureSeed = CaptureSeed(voice: true)
                    router.heldVoiceCapture = false
                } else if let seed = router.heldVoiceAsk {
                    let text = environment.voice.transcript
                    router.heldVoiceAsk = nil
                    environment.voice.reset()
                    Task { await environment.sendHeldVoiceAsk(text: text, seed: seed) }
                }
            } else if phase == .cancelled || phase == .idle {
                router.heldVoiceAsk = nil; router.heldVoiceCapture = false
            }
        }
    }
}
