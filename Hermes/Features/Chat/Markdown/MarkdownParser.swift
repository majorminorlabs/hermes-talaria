import Foundation

/// Block-level Markdown, enough for agent output: headings, paragraphs,
/// lists, quotes, fenced code, tables and rules. Inline syntax is handled by
/// `AttributedString(markdown:)` at render time. Tolerates partial input so
/// streaming text renders sensibly mid-response.
nonisolated enum MarkdownBlock: Hashable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case list(ordered: Bool, items: [MarkdownListItem])
    case quote(String)
    case code(language: String?, code: String)
    case table(MarkdownTable)
    case rule
}

nonisolated struct MarkdownListItem: Hashable, Sendable {
    var marker: String
    var text: String
    var level: Int
    var checked: Bool?
}

nonisolated struct MarkdownTable: Hashable, Sendable {
    enum Alignment: Hashable, Sendable { case leading, center, trailing }
    var header: [String]
    var alignments: [Alignment]
    var rows: [[String]]
}

nonisolated enum MarkdownParser {
    static func parse(_ text: String) -> [MarkdownBlock] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var index = 0
        var paragraph: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph.removeAll()
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code (unterminated fences run to the end while streaming).
            if trimmed.hasPrefix("```") {
                flushParagraph()
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[index])
                    index += 1
                }
                index += 1
                blocks.append(.code(language: language.isEmpty ? nil : language, code: code.joined(separator: "\n")))
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if let heading = headingLevel(trimmed) {
                flushParagraph()
                blocks.append(.heading(level: heading, text: String(trimmed.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces)))
                index += 1
                continue
            }

            if isRule(trimmed) {
                flushParagraph()
                blocks.append(.rule)
                index += 1
                continue
            }

            // Table: a row with pipes followed by a separator row.
            if trimmed.contains("|"), index + 1 < lines.count, isTableSeparator(lines[index + 1]) {
                flushParagraph()
                let header = cells(trimmed)
                let alignments = cells(lines[index + 1]).map(alignment)
                var rows: [[String]] = []
                index += 2
                while index < lines.count, lines[index].contains("|"), !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    var row = cells(lines[index])
                    if row.count < header.count { row += Array(repeating: "", count: header.count - row.count) }
                    rows.append(Array(row.prefix(header.count)))
                    index += 1
                }
                let paddedAlignments = alignments + Array(repeating: .leading, count: max(0, header.count - alignments.count))
                blocks.append(.table(MarkdownTable(header: header, alignments: paddedAlignments, rows: rows)))
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quote: [String] = []
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    quote.append(String(lines[index].trimmingCharacters(in: .whitespaces).dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(.quote(quote.joined(separator: "\n")))
                continue
            }

            if let first = listItem(line) {
                flushParagraph()
                var items = [first.item]
                let ordered = first.ordered
                index += 1
                while index < lines.count {
                    let next = lines[index]
                    if let item = listItem(next), item.ordered == ordered || item.item.level > 0 {
                        items.append(item.item)
                        index += 1
                    } else if !next.trimmingCharacters(in: .whitespaces).isEmpty, next.hasPrefix("  "), !items.isEmpty {
                        items[items.count - 1].text += " " + next.trimmingCharacters(in: .whitespaces)
                        index += 1
                    } else {
                        break
                    }
                }
                blocks.append(.list(ordered: ordered, items: items))
                continue
            }

            paragraph.append(line)
            index += 1
        }
        flushParagraph()
        return blocks
    }

    // MARK: Helpers

    private static func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    private static func isRule(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("-"), trimmed.contains("|") || trimmed.hasPrefix(":") || trimmed.hasPrefix("-") else { return false }
        return trimmed.allSatisfy { "|:- ".contains($0) }
    }

    private static func cells(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func alignment(_ cell: String) -> MarkdownTable.Alignment {
        let left = cell.hasPrefix(":"), right = cell.hasSuffix(":")
        if left && right { return .center }
        if right { return .trailing }
        return .leading
    }

    private static func listItem(_ line: String) -> (item: MarkdownListItem, ordered: Bool)? {
        let indent = line.prefix { $0 == " " }.count
        let body = line.dropFirst(indent)
        let level = indent / 2
        if let first = body.first, "-*+".contains(first), body.dropFirst().first == " " {
            var text = String(body.dropFirst(2))
            var checked: Bool?
            if text.hasPrefix("[ ] ") { checked = false; text.removeFirst(4) }
            else if text.lowercased().hasPrefix("[x] ") { checked = true; text.removeFirst(4) }
            return (MarkdownListItem(marker: "•", text: text, level: level, checked: checked), false)
        }
        let digits = body.prefix { $0.isNumber }
        if !digits.isEmpty, digits.count < 4 {
            let rest = body.dropFirst(digits.count)
            if let delimiter = rest.first, ".)".contains(delimiter), rest.dropFirst().first == " " {
                return (MarkdownListItem(marker: "\(digits).", text: String(rest.dropFirst(2)), level: level, checked: nil), true)
            }
        }
        return nil
    }
}
