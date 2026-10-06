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
        let state = Self.project(runs: runs, profiles: profiles)
        let uncertainIDs = Set(runs.filter { [.unknown, .disconnected, .failed, .cancelled].contains($0.state) }.map(\.id))
        // Serialize ActivityKit updates so an older snapshot cannot overwrite a newer one.
        let previous = productionTask
        productionTask = Task { await previous?.value; await publish(state, demo: false, uncertainIDs: uncertainIDs) }
    }

    static func project(runs: [Run], profiles: ProfileStore) -> HermesActivityAttributes.ContentState {
        // Unknown outcomes are recovery items in Talaria, not confirmed blockers.
        let visible = runs.filter { $0.state.isActive && $0.state != .disconnected }
        let state = HermesActivityAttributes.ContentState(runs: visible.map { run in
            let profile = run.profileID.flatMap { profiles.profiles[$0] }
            let status: HermesActivityAttributes.Run.State = switch run.state {
            case .waitingForApproval, .waitingForInput: .needsInput
            default: .running
            }
            return .init(id: run.id, title: run.title, botName: profile?.name ?? "Hermes", botColor: Self.hex(profile?.tint), state: status, threadID: run.conversationID)
        })
        return state
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

    struct ActivitySnapshot {
        var id: String
        var state: ActivityState
        var isDemo: Bool
    }

    static func retainedID(snapshots: [ActivitySnapshot], currentID: String?, demo: Bool, allowEnded: Bool) -> String? {
        let matching = snapshots.filter { $0.isDemo == demo }
        let live = matching.filter { $0.state == .active || $0.state == .stale }
        if let current = live.first(where: { $0.id == currentID }) { return current.id }
        if let existing = live.first { return existing.id }
        if allowEnded {
            return matching.first(where: { $0.id == currentID && $0.state == .ended })?.id
                ?? matching.first(where: { $0.state == .ended })?.id
        }
        return nil
    }

    private func publish(_ state: HermesActivityAttributes.ContentState, demo: Bool, uncertainIDs: Set<String> = []) async {
        let content = ActivityContent(state: state, staleDate: demo ? nil : .now.addingTimeInterval(60))
        let existing = Activity<HermesActivityAttributes>.activities
        let keepID = Self.retainedID(snapshots: existing.map { .init(id: $0.id, state: $0.activityState, isDemo: $0.attributes.isDemo) }, currentID: activity?.id, demo: demo, allowEnded: state.activeCount == 0)
        activity = existing.first { $0.id == keepID }
        // Enforce one aggregate, including after a relaunch or an older buggy build.
        for extra in existing where extra.id != keepID {
            await extra.end(nil, dismissalPolicy: .immediate)
        }
        if state.activeCount == 0 {
            if let activity, activity.activityState == .active || activity.activityState == .stale {
                let uncertain = !Set(activity.content.state.activeRuns.map(\.id)).isDisjoint(with: uncertainIDs)
                await activity.end(content, dismissalPolicy: uncertain ? .immediate : .after(.now.addingTimeInterval(8)))
                if demo { message = "All done" }
            }
        } else if let activity, activity.activityState == .active || activity.activityState == .stale {
            await activity.update(content)
        } else {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { message = "Enable Live Activities for Talaria in Settings"; return }
            do { activity = try Activity.request(attributes: HermesActivityAttributes(isDemo: demo), content: content, pushType: nil) }
            catch { message = "Live Activity could not start: \(error.localizedDescription)" }
        }
        let liveCount = Activity<HermesActivityAttributes>.activities.filter { $0.activityState == .active || $0.activityState == .stale }.count
        Logger(subsystem: "Talaria.LiveActivity", category: "Aggregate").notice("live=\(liveCount) runs=\(state.activeCount) removed=\(existing.filter { $0.id != keepID }.count)")
    }
    private static func hex(_ tint: ProfileTint?) -> String {
        switch tint { case .teal: "14B8A6"; case .amber: "F59E0B"; case .rose: "EC4899"; case .olive: "84A34A"; case .slate: "64748B"; default: "6366F1" }
    }
}
