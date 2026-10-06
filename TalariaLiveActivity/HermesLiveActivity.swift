import ActivityKit
import SwiftUI
import WidgetKit
import TalariaActivityShared

private extension HermesActivityAttributes.Run.State {
    var color: Color {
        switch self { case .running, .done: .green; case .needsInput: .orange; case .blocked: .red }
    }
}

struct StatusRing: View {
    let state: HermesActivityAttributes.ContentState
    var size: CGFloat = 30
    var body: some View {
        ZStack {
            if state.activeCount == 0 {
                Image(systemName: "checkmark.circle.fill").resizable().scaledToFit().foregroundStyle(.green)
            } else {
                let count = state.activeCount
                let gap = min(0.018, 0.1 / CGFloat(count))
                ForEach(Array(state.activeRuns.enumerated()), id: \.element.id) { index, run in
                    Circle().trim(from: CGFloat(index) / CGFloat(count) + gap, to: CGFloat(index + 1) / CGFloat(count) - gap)
                        .stroke(run.state.color, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                }
                HStack(spacing: 1) {
                    Text("\(state.activeCount)").contentTransition(.numericText())
                    if state.worstState == .needsInput { Text("!").foregroundStyle(.orange) }
                    if state.worstState == .blocked { Text("×").foregroundStyle(.red) }
                }.font(.system(size: size * 0.36, weight: .bold, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
            }
        }.padding(2).frame(width: size, height: size)
            .animation(.default, value: state)
            .accessibilityElement(children: .ignore).accessibilityLabel("\(state.activeCount) active runs, \(state.label)")
    }
}

private struct RunRows: View {
    let state: HermesActivityAttributes.ContentState
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(state.displayRuns) { run in
                Link(destination: run.url) {
                    HStack(spacing: 8) {
                        Circle().fill(botColor(run.botColor)).frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(run.title).font(.system(size: 14, weight: .medium)).lineLimit(1).minimumScaleFactor(0.65)
                            Text("\(run.botName) · \(run.detail)").font(.system(size: 11)).foregroundStyle(run.state.color).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        Spacer(minLength: 0)
                        if run.state == .needsInput { Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.orange) }
                    }
                }.accessibilityLabel("\(run.botName), \(run.title), \(run.detail)")
            }
        }
    }
    private func botColor(_ hex: String) -> Color {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x6366F1
        return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}

struct HermesActivityCard: View {
    let state: HermesActivityAttributes.ContentState
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StatusRing(state: state)
                Text(state.activeCount == 0 ? "All done" : "Hermes · \(state.label)").font(.system(size: 15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.75)
                Spacer(minLength: 4)
                Link("Open", destination: HermesActivityAttributes.ContentState.threadsURL).font(.system(size: 13, weight: .semibold))
            }
            RunRows(state: state)
        }.padding(12).foregroundStyle(.white)
    }
}

struct HermesLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HermesActivityAttributes.self) { context in
            HermesActivityCard(state: context.state)
                .activityBackgroundTint(.black.opacity(0.9)).activitySystemActionForegroundColor(.white)
                .widgetURL(HermesActivityAttributes.ContentState.threadsURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { StatusRing(state: context.state).padding(.leading, 4) }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.label).font(.system(size: 14, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7).foregroundStyle(context.state.worstState.color)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        RunRows(state: context.state)
                        Link("Open", destination: HermesActivityAttributes.ContentState.threadsURL).font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity, alignment: .trailing)
                    }.padding(.horizontal, 4)
                }
            } compactLeading: {
                StatusRing(state: context.state, size: 25)
            } compactTrailing: {
                Text(context.state.label).font(.system(size: 11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.75).foregroundStyle(context.state.worstState.color)
            } minimal: {
                StatusRing(state: context.state, size: 25)
            }.widgetURL(HermesActivityAttributes.ContentState.threadsURL).keylineTint(context.state.worstState.color)
        }
    }
}

@main
struct TalariaLiveActivityBundle: WidgetBundle { var body: some Widget { HermesLiveActivity() } }

#Preview("Lock Screen", as: .content, using: HermesActivityAttributes(isDemo: true)) { HermesLiveActivity() } contentStates: {
    HermesActivityFixtures.frame(0)
    HermesActivityFixtures.frame(1)
    HermesActivityFixtures.frame(2)
    HermesActivityFixtures.frame(3)
    HermesActivityFixtures.frame(4)
    HermesActivityFixtures.blocked
    HermesActivityFixtures.frame(5)
}
#Preview("Compact", as: .dynamicIsland(.compact), using: HermesActivityAttributes(isDemo: true)) { HermesLiveActivity() } contentStates: {
    HermesActivityFixtures.frame(0)
    HermesActivityFixtures.frame(2)
    HermesActivityFixtures.blocked
    HermesActivityFixtures.frame(5)
}
#Preview("Minimal", as: .dynamicIsland(.minimal), using: HermesActivityAttributes(isDemo: true)) { HermesLiveActivity() } contentStates: {
    HermesActivityFixtures.frame(0)
    HermesActivityFixtures.frame(2)
    HermesActivityFixtures.blocked
    HermesActivityFixtures.frame(5)
}
#Preview("Expanded", as: .dynamicIsland(.expanded), using: HermesActivityAttributes(isDemo: true)) { HermesLiveActivity() } contentStates: {
    HermesActivityFixtures.frame(0)
    HermesActivityFixtures.frame(2)
    HermesActivityFixtures.blocked
    HermesActivityFixtures.frame(5)
}
#Preview("Largest standard type") {
    HermesActivityCard(state: HermesActivityFixtures.frame(2)).dynamicTypeSize(.xxxLarge).frame(width: 370).background(.black)
}
