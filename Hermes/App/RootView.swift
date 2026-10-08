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
        .overlay { HeldVoiceOverlay().ignoresSafeArea() }
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
                NavigationStack(path: router.path(for: .now)) { NowView().routeDestinations() }.padding(.top, 12)
            }.badge(environment.needsYou.actionableCount)
            Tab("Threads", systemImage: "bubble.left.and.text.bubble.right", value: AppTab.threads) {
                NavigationStack(path: router.path(for: .threads)) { ThreadsView().routeDestinations() }.padding(.top, 12)
            }
            Tab("Agents", systemImage: "person.2", value: AppTab.agents) {
                NavigationStack(path: router.path(for: .agents)) { BotsView().routeDestinations() }.padding(.top, 12)
            }
        }
    }
}
/// The small pointer joining the held-voice card to its button. The edge
/// stroke matches the card's accent outline; the fill covers the card's own
/// outline where they meet.
private struct HeldVoicePointer: View {
    var up: Bool
    var body: some View {
        ZStack {
            Triangle(up: up, closed: true).fill(Theme.panel)
            Triangle(up: up, closed: false).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, lineJoin: .round))
        }
    }
    private struct Triangle: Shape {
        var up: Bool
        var closed: Bool
        func path(in rect: CGRect) -> Path {
            var path = Path()
            let tip = CGPoint(x: rect.midX, y: up ? rect.minY : rect.maxY)
            let base = up ? rect.maxY : rect.minY
            path.move(to: CGPoint(x: rect.minX, y: base)); path.addLine(to: tip); path.addLine(to: CGPoint(x: rect.maxX, y: base))
            if closed { path.closeSubpath() }
            return path
        }
    }
}

/// Recording feedback for a held Ask, attached to the button being held.
private struct HeldVoiceOverlay: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router
    private var targetName: String { environment.profiles.name(router.heldVoiceAsk?.agentID ?? Profile.defaultID) }
    private var isActive: Bool { router.heldVoiceAsk != nil || router.heldVoiceCapture }
    var body: some View {
        // Window coordinates (the overlay ignores safe areas), matching the
        // anchor's `.global` frame. The card hangs from the button being held.
        GeometryReader { geometry in
            let size = geometry.size
            let anchor = router.heldVoiceAnchor ?? CGRect(x: size.width - 64, y: 80, width: 44, height: 44)
            let width = min(360, size.width - 24)
            let minX = min(max(12, anchor.midX + 36 - width), size.width - 12 - width)
            let below = anchor.midY < size.height / 2
            let pointer = anchor.midX - minX
            if isActive {
                VStack(spacing: 0) {
                    if below { HeldVoicePointer(up: true).frame(width: 20, height: 10).offset(x: pointer - width / 2, y: 1).zIndex(1) }
                    ScrollView {
                        VoiceOverlay(session: environment.voice, send: { _, _ in }, edit: { _ in }, allowAutoSend: false,
                                     targetName: targetName, sendOnStop: router.heldVoiceAsk != nil)
                    }.fixedSize(horizontal: false, vertical: true).frame(maxHeight: 400).scrollBounceBehavior(.basedOnSize)
                    if !below { HeldVoicePointer(up: false).frame(width: 20, height: 10).offset(x: pointer - width / 2, y: -1).zIndex(1) }
                }
                .frame(width: width)
                .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: below ? .topLeading : .bottomLeading)
                .offset(x: minX, y: below ? anchor.maxY + 4 : -(size.height - anchor.minY + 4))
                .transition(.scale(scale: 0.25, anchor: UnitPoint(x: pointer / width, y: below ? 0 : 1)).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.28, bounce: 0.15), value: isActive)
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
