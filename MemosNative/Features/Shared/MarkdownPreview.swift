import SwiftUI

struct MarkdownPreview: View {
    let content: String
    var compact = false
    var onToggleTask: ((Int, Bool) -> Void)?

    private var blocks: [MarkdownBlock] {
        let parsed = MarkdownParser.blocks(from: content)
        return compact ? Array(parsed.prefix(8)) : parsed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 9) {
            ForEach(blocks) { block in
                blockView(block)
            }
            if compact && MarkdownParser.blocks(from: content).count > blocks.count {
                Text("…")
                    .font(.body)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block.kind {
        case .heading(let level, let text):
            InlineMarkdown(text: text)
                .font(level == 1 ? .title3.bold() : level == 2 ? .headline : .subheadline.bold())
                .padding(.top, compact ? 1 : 4)
        case .task(let checked, let text):
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Button {
                    onToggleTask?(block.lineIndex, !checked)
                } label: {
                    Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(checked ? AppTheme.tint : Color.secondary.opacity(0.55))
                        .font(.body)
                }
                .buttonStyle(.plain)
                .disabled(onToggleTask == nil)
                .accessibilityLabel(checked ? "Mark task incomplete" : "Mark task complete")
                InlineMarkdown(text: text)
                    .strikethrough(checked, color: .secondary)
                    .foregroundStyle(checked ? .secondary : .primary)
            }
        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                Capsule()
                    .fill(AppTheme.tint.opacity(0.65))
                    .frame(width: 3)
                InlineMarkdown(text: text)
                    .foregroundStyle(.secondary)
                    .italic()
            }
        case .code(let text):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
            }
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        case .paragraph(let text):
            InlineMarkdown(text: text)
                .font(.body)
        case .spacer:
            Color.clear.frame(height: compact ? 1 : 4)
        }
    }
}

private struct InlineMarkdown: View {
    let text: String

    var body: some View {
        Text(attributed)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributed: AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}

private struct MarkdownBlock: Identifiable {
    enum Kind {
        case heading(Int, String)
        case task(Bool, String)
        case quote(String)
        case code(String)
        case paragraph(String)
        case spacer
    }

    let id: Int
    let lineIndex: Int
    let kind: Kind
}

private enum MarkdownParser {
    static func blocks(from content: String) -> [MarkdownBlock] {
        let lines = content.components(separatedBy: .newlines)
        var blocks: [MarkdownBlock] = []
        var lineIndex = 0
        var identifier = 0

        while lineIndex < lines.count {
            let line = lines[lineIndex]
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                let start = lineIndex
                lineIndex += 1
                var codeLines: [String] = []
                while lineIndex < lines.count,
                      !lines[lineIndex].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[lineIndex])
                    lineIndex += 1
                }
                if lineIndex < lines.count { lineIndex += 1 }
                blocks.append(.init(id: identifier, lineIndex: start, kind: .code(codeLines.joined(separator: "\n"))))
                identifier += 1
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let kind: MarkdownBlock.Kind
            if trimmed.isEmpty {
                kind = .spacer
            } else if let heading = heading(from: trimmed) {
                kind = .heading(heading.level, heading.text)
            } else if let task = task(from: trimmed) {
                kind = .task(task.checked, task.text)
            } else if trimmed.hasPrefix(">") {
                kind = .quote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
            } else {
                kind = .paragraph(line)
            }
            blocks.append(.init(id: identifier, lineIndex: lineIndex, kind: kind))
            identifier += 1
            lineIndex += 1
        }
        return blocks
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        let count = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(count), line.dropFirst(count).first == " " else { return nil }
        return (count, String(line.dropFirst(count + 1)))
    }

    private static func task(from line: String) -> (checked: Bool, text: String)? {
        let lower = line.lowercased()
        if lower.hasPrefix("- [ ] ") {
            return (false, String(line.dropFirst(6)))
        }
        if lower.hasPrefix("- [x] ") {
            return (true, String(line.dropFirst(6)))
        }
        return nil
    }
}
