import SwiftUI
import UIKit

/// Renders agent Markdown with native text, code blocks and tables.
struct MarkdownView: View {
    var text: String

    var body: some View {
        let blocks = MarkdownCache.blocks(for: text)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarkdownBlockView: View {
    var block: MarkdownBlock

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(InlineMarkdown.render(text))
                .font(level == 1 ? .title3.weight(.semibold) : level == 2 ? .headline : .subheadline.weight(.semibold))
                .padding(.top, 4)
                .accessibilityAddTraits(.isHeader)

        case .paragraph(let text):
            Text(InlineMarkdown.render(text))
                .fixedSize(horizontal: false, vertical: true)

        case .list(_, let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        marker(item)
                        Text(InlineMarkdown.render(item.text))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(item.level) * 18)
                }
            }

        case .quote(let text):
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color(uiColor: .tertiaryLabel))
                    .frame(width: 3)
                Text(InlineMarkdown.render(text))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .code(let language, let code):
            CodeBlockView(language: language, code: code)

        case .table(let table):
            MarkdownTableView(table: table)

        case .rule:
            Divider().padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func marker(_ item: MarkdownListItem) -> some View {
        if let checked = item.checked {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .foregroundStyle(checked ? Color.accentColor : .secondary)
        } else {
            Text(item.marker)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: item.marker == "•" ? 10 : 18, alignment: .trailing)
        }
    }
}

/// Inline Markdown → AttributedString, with inline code given a subtle background.
enum InlineMarkdown {
    static func render(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
        var attributed = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        for run in attributed.runs where run.inlinePresentationIntent?.contains(.code) == true {
            attributed[run.range].backgroundColor = Color(uiColor: .tertiarySystemFill)
            attributed[run.range].font = .system(.callout, design: .monospaced)
        }
        return attributed
    }
}

/// Parsed blocks keyed by source text; streaming re-renders hit this often.
enum MarkdownCache {
    private static var storage: [String: [MarkdownBlock]] = [:]

    static func blocks(for text: String) -> [MarkdownBlock] {
        if let cached = storage[text] { return cached }
        let blocks = MarkdownParser.parse(text)
        if storage.count > 300 { storage.removeAll(keepingCapacity: true) }
        storage[text] = blocks
        return blocks
    }
}

// MARK: - Code

struct CodeBlockView: View {
    var language: String?
    var code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language?.lowercased() ?? "code")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)

            Divider()

            ScrollView(.horizontal, showsIndicators: false) {
                Text(SyntaxHighlighter.highlight(code, language: language))
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
            }
        }
        .background(Theme.codeBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.hairline.opacity(0.5), lineWidth: 0.5)
        }
    }
}

/// Lightweight highlighting: comments, strings, numbers and common keywords.
enum SyntaxHighlighter {
    private static let keywords: Set<String> = [
        "func", "let", "var", "if", "else", "guard", "return", "for", "in", "while", "struct", "class", "enum", "case",
        "switch", "import", "async", "await", "try", "throws", "defer", "self", "true", "false", "nil", "def", "from",
        "as", "with", "lambda", "None", "True", "False", "const", "function", "export", "interface", "type", "fn",
        "pub", "impl", "mut", "use", "package", "public", "private", "static", "extension", "protocol",
    ]

    static func highlight(_ code: String, language: String?) -> AttributedString {
        var attributed = AttributedString(code)
        let language = language?.lowercased() ?? ""
        if language == "diff" {
            for line in code.split(separator: "\n", omittingEmptySubsequences: false) {
                guard let range = attributed.range(of: String(line)) else { continue }
                if line.hasPrefix("+") { attributed[range].foregroundColor = Theme.success }
                if line.hasPrefix("-") { attributed[range].foregroundColor = Theme.failure }
            }
            return attributed
        }
        guard !["text", "txt", "plain", "output", "console"].contains(language) else { return attributed }

        let nsCode = code as NSString
        func apply(_ pattern: String, _ color: Color, options: NSRegularExpression.Options = []) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            for match in regex.matches(in: code, range: NSRange(location: 0, length: nsCode.length)) {
                guard let range = Range(match.range, in: code), let attributedRange = Range(range, in: attributed) else { continue }
                attributed[attributedRange].foregroundColor = color
            }
        }

        apply(#"\b\d+(\.\d+)?\b"#, Color(uiColor: .systemBlue))
        let words = keywords.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        apply("\\b(\(words))\\b", Color(uiColor: .systemPink))
        apply(#""(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*'"#, Color(uiColor: .systemOrange))
        let comment = ["python", "py", "bash", "sh", "zsh", "shell", "yaml", "yml", "toml", "ruby", "rb"].contains(language) ? "#[^\n]*" : "//[^\n]*"
        apply(comment, Color(uiColor: .secondaryLabel))
        return attributed
    }
}

// MARK: - Tables

struct MarkdownTableView: View {
    var table: MarkdownTable
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ViewBuilder
    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            accessibleRows
        } else {
            grid
        }
    }

    // Grid's bidirectional column sizing can loop inside the transcript's lazy
    // stack at accessibility sizes. Vertical rows need no cross-cell measurement,
    // retain every value, and let large text wrap without truncation.
    private var accessibleRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            if table.rows.isEmpty {
                ForEach(Array(table.header.enumerated()), id: \.offset) { _, heading in
                    Text(InlineMarkdown.render(heading)).font(.subheadline.weight(.semibold)).padding(10)
                }
            }
            ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIndex, row in
                if rowIndex > 0 { Divider() }
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(table.header.enumerated()), id: \.offset) { column, heading in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(InlineMarkdown.render(heading))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(InlineMarkdown.render(column < row.count ? row[column] : ""))
                                .font(.body.monospacedDigit())
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
        }
        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("markdown-table-accessible")
    }

    private var grid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(table.header.enumerated()), id: \.offset) { column, cell in
                        cellView(cell, column: column)
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .background(Color(uiColor: .tertiarySystemFill))

                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    Divider().gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { column, cell in
                            cellView(cell, column: column)
                                .font(.subheadline.monospacedDigit())
                        }
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.hairline.opacity(0.6), lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .accessibilityIdentifier("markdown-table-grid")
    }

    private func cellView(_ text: String, column: Int) -> some View {
        let alignment = column < table.alignments.count ? table.alignments[column] : .leading
        return Text(InlineMarkdown.render(text))
            .lineLimit(3)
            .frame(minWidth: 56, maxWidth: 240, alignment: alignment.frameAlignment)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .gridColumnAlignment(alignment.horizontal)
    }
}

private extension MarkdownTable.Alignment {
    var frameAlignment: Alignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    var horizontal: HorizontalAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

#Preview {
    ScrollView {
        MarkdownView(text: """
        ## Results

        Local wins on **time-to-first-token**, but `throughput` is lower. See [the docs](https://example.com).

        | Provider | p50 | p95 |
        |:--|--:|--:|
        | OpenRouter | 412 ms | 1.18 s |
        | Local | 95 ms | 140 ms |

        1. First item
        2. Second item
           - nested

        > A quote worth noting.

        ```python
        def quantize(x, bits=8):  # comment
            return round(x / scale)
        ```
        """)
        .padding()
    }
}
