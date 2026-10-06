@preconcurrency import ActivityKit
import SwiftUI
import UIKit
import OSLog
import TalariaActivityShared

@Observable
final class HermesLiveActivityController {
    static var demoEnabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-TalariaDemo"), args.indices.contains(index + 1) else { return false }
        return args[index + 1].uppercased() == "YES"
    }
    private(set) var demoRunning = false
    private(set) var message = ""
    @ObservationIgnored private var activity: Activity<HermesActivityAttributes>?
    @ObservationIgnored private var demoTask: Task<Void, Never>?
    @ObservationIgnored private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    @ObservationIgnored private var productionTask: Task<Void, Never>?

    func update(runs: [Run], profiles: ProfileStore, connected: Bool) {
        guard !Self.demoEnabled, connected else { return }
        let visible = runs.filter { $0.state.isActive || $0.state == .unknown }
        let state = HermesActivityAttributes.ContentState(runs: visible.map { run in
            let profile = run.profileID.flatMap { profiles.profiles[$0] }
            let status: HermesActivityAttributes.Run.State = switch run.state {
            case .waitingForApproval, .waitingForInput: .needsInput
            case .unknown, .disconnected, .failed: .blocked
            default: .running
            }
            return .init(id: run.id, title: run.title, botName: profile?.name ?? "Hermes", botColor: Self.hex(profile?.tint), state: status, threadID: run.conversationID)
        })
        // Serialize ActivityKit updates so an older snapshot cannot overwrite a newer one.
        let previous = productionTask
        productionTask = Task { await previous?.value; await publish(state, demo: false) }
    }

    func startDemo() {
        guard Self.demoEnabled, !demoRunning else { return }
        demoRunning = true; message = "Demo running — go Home"
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Talaria Live Activity demo") { [weak self] in
            self?.demoTask?.cancel()
        }
        demoTask = Task {
            let existing = Activity<HermesActivityAttributes>.activities
            for item in existing { await item.end(nil, dismissalPolicy: .immediate) }
            activity = nil
            let start = ContinuousClock.now
            do {
                for index in HermesActivityFixtures.offsets.indices {
                    try await Task.sleep(until: start.advanced(by: .seconds(HermesActivityFixtures.offsets[index])), clock: .continuous)
                    try Task.checkCancellation()
                    let frame = HermesActivityFixtures.frame(index)
                    await publish(frame, demo: true)
                    Logger(subsystem: "Talaria.LiveActivity", category: "Demo").notice("frame=\(index) count=\(frame.activeCount) state=\(frame.label, privacy: .public) background=\(UIApplication.shared.applicationState == .background)")
                    if activity == nil && index == 0 { break }
                }
                // Hold the finite background assertion through the dismissal deadline.
                if activity != nil { try await Task.sleep(until: start.advanced(by: .seconds(27)), clock: .continuous) }
            } catch {
                if let activity { await activity.end(nil, dismissalPolicy: .immediate) }
                message = "Demo interrupted"
            }
            demoRunning = false
            if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid }
        }
    }

    private func publish(_ state: HermesActivityAttributes.ContentState, demo: Bool) async {
        let content = ActivityContent(state: state, staleDate: demo ? nil : .now.addingTimeInterval(60))
        if activity == nil {
            activity = Activity<HermesActivityAttributes>.activities.first { $0.activityState == .active && $0.attributes.isDemo == demo }
        }
        if state.activeCount == 0 {
            if let activity {
                await activity.end(content, dismissalPolicy: .after(.now.addingTimeInterval(8)))
                if demo { message = "All done" }
            }
            if !demo { activity = nil }
        } else if let activity, activity.activityState == .active {
            await activity.update(content)
        } else {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { message = "Enable Live Activities for Talaria in Settings"; return }
            do { activity = try Activity.request(attributes: HermesActivityAttributes(isDemo: demo), content: content, pushType: nil) }
            catch { message = "Live Activity could not start: \(error.localizedDescription)" }
        }
    }
    private static func hex(_ tint: ProfileTint?) -> String {
        switch tint { case .teal: "14B8A6"; case .amber: "F59E0B"; case .rose: "EC4899"; case .olive: "84A34A"; case .slate: "64748B"; default: "6366F1" }
    }
}
