import SwiftUI
import UIKit

// MARK: - Brand

/// The canonical Talaria mark (the winged sandal) on its white tile, as on the
/// Home Screen. Brand moments only: About, the unpaired welcome, pairing.
struct TalariaMark: View {
    var size: CGFloat = 64

    var body: some View {
        Image("TalariaMark")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .padding(size * 0.12)
            .frame(width: size, height: size)
            .background(.white, in: RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
            }
            .accessibilityElement()
            .accessibilityLabel("Talaria")
            .accessibilityAddTraits(.isImage)
    }
}

// MARK: - Tag

/// Small status/metadata tag (Desktop's Badge): tinted fill, matching text,
/// app radius rather than a full pill.
struct Tag: View {
    enum Tone: Hashable {
        case accent, muted, success, attention, failure
        case custom(Color)

        var color: Color {
            switch self {
            case .accent: .accentColor
            case .muted: .secondary
            case .success: Theme.success
            case .attention: Theme.attention
            case .failure: Theme.failure
            case .custom(let color): color
            }
        }
    }

    var text: String
    var tone: Tone = .muted
    var symbol: String? = nil

    init(_ text: String, tone: Tone = .muted, symbol: String? = nil) {
        self.text = text
        self.tone = tone
        self.symbol = symbol
    }

    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(tone.color)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(fill, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .lineLimit(1)
        .fixedSize()
    }

    private var fill: Color {
        tone == .muted ? Color(uiColor: .tertiarySystemFill) : tone.color.opacity(0.13)
    }
}

// MARK: - Panel

extension View {
    /// Desktop's widget shell: a soft fill, no border. `tint` washes the fill
    /// for attention/failure states without adding a frame.
    func panel(tint: Color? = nil, padding: CGFloat = 14, cornerRadius: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.panel)
                    .overlay {
                        if let tint {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(tint.opacity(0.07))
                        }
                    }
            }
    }
}

// MARK: - Flow layout

/// Wraps children onto as many lines as needed (tag clouds, chips).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + CGFloat(max(0, rows.count - 1)) * lineSpacing
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width && !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}

/// Names as quiet chips that wrap, with an inline "Show all" past `limit`.
/// Each chip stays a separate static text so VoiceOver and UI tests can find it.
struct TagCloud: View {
    var items: [String]
    var limit: Int = 18
    var monospaced = false
    @State private var expanded = false

    var body: some View {
        let shown = expanded ? items : Array(items.prefix(limit))
        VStack(alignment: .leading, spacing: 10) {
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(shown, id: \.self) { item in
                    Text(item)
                        .font(monospaced ? .footnote.monospaced() : .footnote)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            if items.count > limit {
                Button(expanded ? "Show Fewer" : "Show All \(items.count)") {
                    withAnimation(.snappy) { expanded.toggle() }
                }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Failure

/// A failure or uncertain outcome: plain title and sentence first, the raw
/// code one tap away under Details (copyable).
struct FailureCallout: View {
    var explanation: StatusCopy.Explanation
    var symbol = "xmark.octagon.fill"
    var tint: Color = Theme.failure
    @State private var showsDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(explanation.title).font(.headline)
            } icon: {
                Image(systemName: symbol).foregroundStyle(tint)
            }
            if let message = explanation.message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if let code = explanation.code {
                Button {
                    withAnimation(.snappy) { showsDetails.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text("Details")
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .rotationEffect(.degrees(showsDetails ? 90 : 0))
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showsDetails ? "Hide details" : "Show details")
                .padding(.top, 2)
                if showsDetails {
                    HStack(alignment: .firstTextBaseline) {
                        Text(code)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Spacer(minLength: 8)
                        Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = code }
                            .labelStyle(.iconOnly)
                            .font(.footnote)
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Copy error code")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
