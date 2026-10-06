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
        shell
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
                Task {
                    if offline { await connection.reconnect() }
                    await environment.refreshAll()
                }
            }
        }
    }

    private var accessoryVisible: Bool {
        let path = router.selectedTab == .now ? router.nowPath : router.selectedTab == .threads ? router.threadsPath : router.agentsPath
        switch path.last { case .thread, .conversation, .newConversation, .run: return false; default: return true }
    }
    @ViewBuilder private var shell: some View {
        if #available(iOS 26.1, *) {
            tabs(fallback: false)
                .tabViewBottomAccessory(isEnabled: accessoryVisible) { AskBar() }
                .tabBarMinimizeBehavior(.onScrollDown)
        } else if #available(iOS 26.0, *) {
            tabs(fallback: false).tabViewBottomAccessory { if accessoryVisible { AskBar() } }.tabBarMinimizeBehavior(.onScrollDown)
        } else { tabs(fallback: true) }
    }
    private func tabs(fallback: Bool) -> some View {
        @Bindable var router = router
        return TabView(selection: $router.selectedTab) {
            Tab("Now", systemImage: "circle.dotted.circle", value: AppTab.now) {
                NavigationStack(path: router.path(for: .now)) { NowView().askInset(enabled: fallback).routeDestinations() }
            }.badge(environment.needsYou.actionableCount)
            Tab("Threads", systemImage: "bubble.left.and.text.bubble.right", value: AppTab.threads) {
                NavigationStack(path: router.path(for: .threads)) { ThreadsView().askInset(enabled: fallback).routeDestinations() }
            }
            Tab("Agents", systemImage: "person.2", value: AppTab.agents) {
                NavigationStack(path: router.path(for: .agents)) { BotsView().askInset(enabled: fallback).routeDestinations() }
            }
        }
    }
}
extension View {
    @ViewBuilder func askInset(enabled: Bool) -> some View {
        if enabled { safeAreaInset(edge: .bottom, spacing: 0) { AskBar().background(.bar) } }
        else { self }
    }
}

/// Keep recording updates out of the native accessory host's view identity.
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
                if router.heldVoiceCapture { router.captureSeed = CaptureSeed(voice: true) }
                else { router.askSeed = router.heldVoiceAsk }
                router.heldVoiceAsk = nil; router.heldVoiceCapture = false
            } else if phase == .cancelled || phase == .idle {
                router.heldVoiceAsk = nil; router.heldVoiceCapture = false
            }
        }
    }
}
