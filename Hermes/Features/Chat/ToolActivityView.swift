import SwiftUI

/// Tool calls from an assistant turn, as Hermes Desktop shows them: quiet
/// one-line rows on a soft panel, no border. Several calls fold behind one
/// summary line; any row expands to its input, output and targets.
struct ToolActivityView: View {
    var calls: [ToolCall]
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if calls.count > 1 {
                Button {
                    withAnimation(.snappy) { expanded.toggle() }
                } label: {
                    summaryRow
                }
                .buttonStyle(.plain)
            }
            if calls.count == 1 || expanded {
                ForEach(Array(calls.enumerated()), id: \.element.id) { index, call in
                    if index > 0 || calls.count > 1 { Divider().padding(.leading, 38) }
                    ToolCallRow(call: call)
                }
                .transition(.opacity)
            }
        }
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var summaryRow: some View {
        let names = calls.reduce(into: [String]()) { result, call in
            if !result.contains(call.displayName) { result.append(call.displayName) }
        }
        let failed = calls.filter { $0.status == .failed }.count
        let running = calls.contains { $0.status == .running }
        return HStack(spacing: 10) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(calls.count) tool calls")
                    .font(.subheadline.weight(.medium))
                Text(names.prefix(3).joined(separator: ", ") + (names.count > 3 ? " +\(names.count - 3)" : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if failed > 0 {
                Tag("\(failed) failed", tone: .failure)
            } else if running {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("All completed")
            }
            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(expanded ? 180 : 0))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(expanded ? "Hides each tool call" : "Shows each tool call")
    }
}

struct ToolCallRow: View {
    var call: ToolCall
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: call.kind.symbol)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    Text(call.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .layoutPriority(1)
                    if let preview = call.preview, !expanded, !call.displayName.localizedCaseInsensitiveContains(preview) {
                        Text(preview)
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 6)
                    statusIcon
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(call.displayName)\(call.preview.map { ", \($0)" } ?? ""), \(call.status.label)")
            .accessibilityHint(expanded ? "Hides details" : "Shows details")

            if expanded {
                details
                    .padding(.leading, 28)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }

    @ViewBuilder private var statusIcon: some View {
        switch call.status {
        case .running: ProgressView().controlSize(.mini)
        case .completed: Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
        case .failed: Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(Theme.failure)
        case .denied: Image(systemName: "hand.raised.slash").font(.caption).foregroundStyle(Theme.attention)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let input = call.input {
                CommandBlock(text: input, prompt: call.kind == .terminal ? "$" : nil)
            }
            if let output = call.output, !output.isEmpty {
                ScrollView {
                    Text(output)
                        .font(.caption.monospaced())
                        .foregroundStyle(call.status == .failed ? Theme.failure : .secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
            }
            if !call.targets.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(call.targets, id: \.self) { target in
                        Label(target, systemImage: call.kind == .browser || call.kind == .web ? "link" : "doc")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            HStack(spacing: 10) {
                Text(call.kind.label)
                Text(call.name).monospaced()
                if let duration = call.duration { Text(Format.elapsed(duration)).monospacedDigit() }
                Text(call.status.label)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }
}

extension ToolCall {
    /// "Skill View", "Ran python analyze.py": the summary, never a repeat of the kind.
    var displayName: String { summary.isEmpty ? kind.label : summary }

    /// The one detail that identifies this call (a path, command, query or
    /// name), pulled from targets or the JSON arguments.
    var preview: String? {
        if let target = targets.first { return target }
        guard let input, !input.isEmpty else { return nil }
        if let data = input.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["command", "path", "file_path", "name", "query", "url", "pattern"] {
                if let value = object[key] as? String, !value.isEmpty { return Self.oneLine(value) }
            }
            if let value = object.values.compactMap({ $0 as? String }).first(where: { !$0.isEmpty }) { return Self.oneLine(value) }
            return nil
        }
        return Self.oneLine(input)
    }

    private static func oneLine(_ text: String) -> String {
        String(text.split(whereSeparator: \.isNewline).first ?? "").trimmingCharacters(in: .whitespaces)
    }
}

#Preview {
    ToolActivityView(calls: MockFixtures.standard().messages["c-cleanup"]![1].toolCalls)
        .padding()
}
