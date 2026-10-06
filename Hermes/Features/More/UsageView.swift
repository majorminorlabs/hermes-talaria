import SwiftUI
import Charts

/// Token and run counts reported by the host. No pricing is derived.
struct UsageView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router
    @State private var period: UsagePeriod = .week
    @State private var report = Resource<UsageReport>()
    @State private var selectedDay: Date?

    var body: some View {
        CapabilityGate(capability: .usage) {
            List {
                Section {
                    Picker("Period", selection: $period) {
                        ForEach(UsagePeriod.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                if let report = report.value {
                    content(report)
                } else if let error = report.phase.error {
                    Section { ErrorContentView(error: error) { await load() } }
                } else {
                    Section { LoadingRows(count: 3) }
                }
            }
        }
        .navigationTitle("Usage")
        .task(id: period) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        await report.load { try await environment.client.usage.usage(period: period) }
    }

    @ViewBuilder
    private func content(_ report: UsageReport) -> some View {
        Section {
            HStack(spacing: 0) {
                StatTile(label: "Tokens", value: Format.tokens(report.totals.total),
                         detail: "\(Format.tokens(report.totals.input)) in · \(Format.tokens(report.totals.output)) out")
                Divider().padding(.vertical, 4)
                StatTile(label: report.sessionCount == nil ? "Runs" : "Sessions", value: "\(report.sessionCount ?? report.runCount)", detail: report.period.label.lowercased())
            }
            .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
        }

        if report.daily.count > 1 {
            Section {
                chart(report)
                    .frame(height: 180)
                    .padding(.vertical, 8)
            } header: {
                SectionHeader("Tokens per day")
            } footer: {
                Text("Touch and drag to inspect a day.")
            }
        }

        if !report.models.isEmpty {
            let total = max(1, report.models.reduce(0) { $0 + $1.usage.total })
            Section {
                ForEach(report.models.sorted { $0.usage.total > $1.usage.total }) { usage in
                    ModelUsageRow(usage: usage, share: Double(usage.usage.total) / Double(total))
                }
            } header: {
                SectionHeader("By Model")
            }
        }

        Section {
            Button("Recent work", systemImage: "clock.arrow.circlepath") { router.selectedTab = .threads }
        } footer: {
            Text("Counts come from Hermes on your Mac. Costs aren't estimated here.")
        }
    }

    private func chart(_ report: UsageReport) -> some View {
        Chart {
            ForEach(report.daily) { day in
                BarMark(x: .value("Day", day.date, unit: .day), y: .value("Tokens", day.tokens), width: .ratio(0.7))
                    .foregroundStyle(Color.accentColor.opacity(selectedDay == nil || isSelected(day) ? 1 : 0.35))
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
                    .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide).month().day()))
                    .accessibilityValue("\(Format.tokens(day.tokens)) tokens, \(day.sessionCount ?? day.runs) \(day.sessionCount == nil ? "runs" : "sessions")")
            }
            if let selected = report.daily.first(where: isSelected) {
                RuleMark(x: .value("Day", selected.date, unit: .day))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selected.date.formatted(.dateTime.weekday(.abbreviated).month().day()))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(Format.tokens(selected.tokens)) tokens")
                                .font(.caption.weight(.semibold))
                            Text("\(selected.sessionCount ?? selected.runs) \(selected.sessionCount == nil ? "runs" : "sessions")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
            }
        }
        .chartXSelection(value: $selectedDay)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Color(uiColor: .quaternaryLabel))
                AxisValueLabel {
                    if let tokens = value.as(Int.self) { Text(Format.tokens(tokens)) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: report.daily.count > 10 ? 7 : 1)) { _ in
                AxisValueLabel(format: report.daily.count > 10 ? .dateTime.month(.abbreviated).day() : .dateTime.weekday(.narrow), centered: true)
            }
        }
    }

    private func isSelected(_ day: DailyUsage) -> Bool {
        guard let selectedDay else { return false }
        return Calendar.current.isDate(day.date, inSameDayAs: selectedDay)
    }
}

private struct StatTile: View {
    var label: String
    var value: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }
}

private struct ModelUsageRow: View {
    var usage: ModelUsage
    var share: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(usage.model.displayName)
                    Text(usage.model.provider).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Format.tokens(usage.usage.total)).monospacedDigit()
                    Text("\(usage.sessionCount ?? usage.runCount) \(usage.sessionCount == nil ? "runs" : "sessions") · \(Format.percent(share))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(uiColor: .tertiarySystemFill))
                    Capsule().fill(Color.accentColor).frame(width: max(4, proxy.size.width * share))
                }
            }
            .frame(height: 4)
            .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack { UsageView() }.previewEnvironment()
}
