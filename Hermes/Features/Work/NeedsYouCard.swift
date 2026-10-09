import SwiftUI

struct NeedsYouGroupCard: View {
    var items: [NeedsYouItem]
    @Environment(AppEnvironment.self) private var environment
    var body: some View {
        if items.count == 1, let item = items.first { NeedsYouCard(item: item) }
        else {
            DisclosureGroup("\(items.count) requests · \(items.first?.request ?? "Needs you")") {
                ForEach(items) { NeedsYouCard(item: $0) }
                if items.allSatisfy({ $0.kind == .intervention && $0.riskTier == .low }) {
                    Button("Dismiss all \(items.count)") { for item in items { environment.snoozes.dismiss(item.id, host: environment.connection.activeHostID) } }
                    if items.allSatisfy({ environment.activity.run($0.runID)?.canRetry == true }) {
                        Button("Retry all") { environment.toasts.perform { for item in items { if let id = item.runID { _ = try await environment.activity.retry(id) } } } }.disabled(!environment.connection.connection.isConnected)
                    }
                }
            }
        }
    }
}
struct NeedsYouCard: View {
    var item: NeedsYouItem
    @Environment(AppEnvironment.self) private var environment
    @State private var answer = ""
    @State private var reviewNote = ""
    @State private var announcedDeadline = 0
    @State private var answering = false
    @State private var sending = false
    @State private var confirmed = false
    @State private var error: String?
    @State private var risk: RiskAction?
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let expired = item.expired(at: context.date)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(environment.profiles.name(item.agentID), systemImage: "hand.raised.fill")
                    Spacer()
                    if let deadline = item.deadline {
                        Text(expired ? "Expired" : "\(max(0, Int(deadline.timeIntervalSince(context.date))))s left")
                            .monospacedDigit().foregroundStyle(deadline.timeIntervalSince(context.date) < 60 ? Theme.failure : Theme.attention)
                    }
                }.font(.footnote).foregroundStyle(Theme.secondaryText)
                Text(item.request).font(.headline)
                if item.kind != .approval, let command = item.approval?.command { CommandBlock(text: command) }
                if item.kind != .approval, let timeout = item.approval?.onTimeout { Text("If you do not answer: " + timeout).font(.footnote).foregroundStyle(Theme.secondaryText) }
                if let details = item.context { Text(details).font(.subheadline).foregroundStyle(Theme.secondaryText).lineLimit(3) }
                responseControls(expired: expired)
                if sending { ProgressView("Sending…") }
                if let error { Text(error).font(.footnote).foregroundStyle(Theme.failure) }
                if !live { Text("Reconnect to answer.").font(.footnote).foregroundStyle(Theme.secondaryText) }
                HStack {
                    if item.kind != .approval { LaterMenu(item: item) }
                    Spacer()
                    if let id = item.workItemID { NavigationLink("Open thread", value: id.hasPrefix("task:") ? Route.task(String(id.dropFirst(5))) : Route.thread(id)) }
                }.font(.footnote)
            }
            .padding(14)
            .background(expired ? Theme.panel : Theme.attentionWash, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Needs you. \(environment.profiles.name(item.agentID)) asks: \(item.request). \(deadlineLabel(at: context.date))")
            .accessibilityIdentifier("needs-you-card-\(item.id)")
            .buttonStyle(.borderless)
            .onChange(of: Int(item.deadline?.timeIntervalSince(context.date) ?? -1)) { _, seconds in
                let threshold = seconds <= 10 ? 10 : seconds <= 60 ? 60 : 0
                if threshold != 0 && threshold != announcedDeadline { announcedDeadline = threshold; UIAccessibility.post(notification: .announcement, argument: "\(threshold) seconds left to answer") }
            }
        }
        .accessibilityActions { ForEach(item.choices, id: \.self) { choice in Button(choice) { if live && !item.expired(at: .now) { respond(choice) } } }; Button("Answer") { answering = true } }
        .haptic(.success, trigger: confirmed)
        .sheet(item: $risk) { RiskConfirmSheet(action: $0) }
    }
    @ViewBuilder private func responseControls(expired: Bool) -> some View {
                if confirmed || environment.needsYou.isConfirmed(item.id) { Label(item.kind == .review ? "Marked done" : item.kind == .intervention ? "Retry requested" : "Answer sent", systemImage: "checkmark") }
                else if expired {
                    Text("Hermes stopped waiting. It may have continued without this.").font(.footnote).foregroundStyle(Theme.secondaryText)
                    Button("Dismiss") { dismiss() }
                } else if item.kind == .approval {
                    if let approval = item.approval {
                        ApprovalCard(approval: approval, style: .plain)
                    }
                } else if item.kind == .question || item.kind == .decision {
                    ForEach(item.choices, id: \.self) { choice in Button(choice + (item.approval?.recommendedChoice == choice ? " · recommended" : "")) { respond(choice) }.frame(minHeight: 44).disabled(!live || sending) }
                    Button(item.choices.isEmpty ? "Answer…" : "Other…") { answering.toggle() }.frame(minHeight: 44).disabled(!live || sending)
                    if answering {
                        TextField("Your answer", text: $answer, axis: .vertical)
                        Button("Voice input") { environment.voice.start(capture: false, simulated: environment.simulator != nil) }
                        if ![.idle,.cancelled].contains(environment.voice.phase) {
                            VoiceOverlay(session: environment.voice, send: { value,_ in answer = value }, edit: { answer = $0 }, allowAutoSend: false, targetName: environment.profiles.name(item.agentID))
                        }
                        Button("Send") { respond(answer) }.disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !live || sending)
                    }
                } else if let id = item.taskID, let task = environment.tasks.task(id) {
                    if item.kind == .review { TextField("Review note (optional)", text: $reviewNote, axis: .vertical) }
                    if item.kind == .review && task.availableTransitions.contains(.completed) { Button("Mark done") { perform { try await environment.client.tasks.review(taskID: id, status: .completed, summary: reviewNote); await environment.tasks.refresh() } }.disabled(!live || sending) }
                    if task.availableTransitions.contains(.ready) {
                        Button(item.kind == .review ? "Send back…" : "Unblock") {
                            risk = RiskAction(verb: "Send back", effect: "Releases this task to its dispatcher again.", target: task.title) { try await environment.client.tasks.review(taskID: id, status: .ready, summary: reviewNote); await environment.tasks.refresh() }
                        }.disabled(!live || sending)
                    }
                } else if let run = environment.activity.run(item.runID) {
                    if run.state == .unknown { Text("Check on your Mac before asking again.").font(.footnote) }
                    else if run.canRetry { Button("Retry") { perform { _ = try await environment.activity.retry(run.id) } }.disabled(!live || sending) }
                    Button("Dismiss") { dismiss() }
                } else if let id = item.routineID {
                    Button("Retry once") { perform { try await environment.client.schedules.runNow(routineID: id) } }.disabled(!live || sending)
                    if let routine = environment.routines.routine(id), routine.isEnabled {
                        Button("Pause routine") { risk = RiskAction(verb: "Pause routine", effect: "Stops future scheduled work until you resume this routine.", target: routine.name) { try await environment.client.schedules.setEnabled(false, routineID: id) } }
                    }
                    Button("Dismiss") { dismiss() }
                } else if item.id.hasPrefix("outbox:") { NavigationLink("Check Outbox", value: Route.outbox)
                } else { Button("Retry") { Task { await environment.refreshAll() } }.disabled(!live) }
    }
    private func deadlineLabel(at date: Date) -> String { guard let deadline = item.deadline else { return "" }; return "\(max(0, Int(deadline.timeIntervalSince(date)))) seconds left" }
    private var live: Bool { environment.connection.connection.isConnected && item.canRespond || environment.connection.connection.isConnected && item.kind == .approval }
    private func dismiss() { environment.snoozes.dismiss(item.id, host: environment.connection.activeHostID) }
    private func respond(_ text: String) { guard !sending, !environment.needsYou.isConfirmed(item.id) else { return }; perform { try await environment.activity.answerClarification(item.id, answer: text) } }
    private func perform(_ action: @escaping () async throws -> Void) {
        sending = true; error = nil
        environment.needsYou.retain(item)
        Task { do { try await action(); confirmed = true; environment.needsYou.confirm(item.id); try? await Task.sleep(for: .seconds(1.2)); dismiss() }
            catch { self.error = StatusCopy.sentence(error.localizedDescription) ?? error.localizedDescription }
            sending = false
            environment.needsYou.release(item.id)
        }
    }
}
struct LaterMenu: View {
    let item: NeedsYouItem
    @Environment(AppEnvironment.self) private var environment
    var body: some View {
        Menu(item.deadline != nil && [.question,.decision].contains(item.kind) ? "Let it lapse" : "Later") {
            if [.question,.decision].contains(item.kind), let deadline = item.deadline {
                Text("Hermes stops waiting at \(deadline.formatted(date: .omitted, time: .shortened)). What it does next is up to Hermes.")
                Button("Let it lapse") { park(.date(deadline)) }
            } else {
                Button("In 1 hour") { park(.date(.now.addingTimeInterval(3600))) }
                Button("Tonight") { park(.date(Calendar.current.nextDate(after: .now, matching: DateComponents(hour: 20, minute: 0), matchingPolicy: .nextTime)!)) }
                Button("Tomorrow morning") { park(.date(Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date.now.addingTimeInterval(86400))!)) }
                Button("At my desk") { park(.atDesk) }
                Text("Shows up here again. Talaria won't notify you.")
            }
        }.accessibilityIdentifier("needs-you-later").frame(minHeight: 44)
    }
    private func park(_ value: Snooze) { environment.snoozes.set(value, id: item.id, host: environment.connection.activeHostID) }
}
struct RiskAction: Identifiable {
    var id = UUID()
    var verb: String
    var effect: String
    var target: String
    var high = false
    var perform: () async throws -> Void
}
struct RiskConfirmSheet: View {
    var action: RiskAction
    @Environment(\.dismiss) private var dismiss
    @State private var sending = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(action.effect).font(.body)
                Text(action.target).font(.subheadline).foregroundStyle(Theme.secondaryText)
                if let error { Text(error).foregroundStyle(Theme.failure) }
                if sending { ProgressView() }
                else if action.high { HoldToConfirmButton(title: "Hold to \(action.verb)", action: submit) }
                else { Button(action.verb, action: submit).accessibilityIdentifier("risk-confirm").buttonStyle(.borderedProminent).frame(minHeight: 44) }
                Button("Cancel") { dismiss() }.frame(minHeight: 44)
            }.padding().navigationTitle(action.verb).navigationBarTitleDisplayMode(.inline)
        }.presentationDetents([.medium])
    }
    private func submit() {
        sending = true
        Task { do { try await action.perform(); dismiss() } catch { self.error = error.localizedDescription; sending = false } }
    }
}
struct HoldToConfirmButton: View {
    var title: String
    var action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var holding = false
    @State private var completed = false
    @State private var progress = 0.0
    var body: some View {
        Text(title).frame(maxWidth: .infinity, minHeight: 44)
            .background(.tint.opacity(0.15), in: Capsule())
            .overlay(alignment: .leading) { GeometryReader { g in Color.accentColor.opacity(0.25).frame(width: g.size.width * progress) }.clipShape(Capsule()).allowsHitTesting(false) }
            .onLongPressGesture(minimumDuration: 1.2, maximumDistance: 25) { holding = false; progress = 0; completed.toggle(); action() } onPressingChanged: { value in
                holding = value; withAnimation(reduceMotion ? nil : .linear(duration: value ? 1.2 : 0.3)) { progress = value ? 1 : 0 }
            }
            .haptic(.impact(weight: .light), trigger: holding)
            .haptic(.success, trigger: completed)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(title).accessibilityHint("Hold for 1.2 seconds to confirm")
    }
}
