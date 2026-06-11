import Foundation

/// Serializes the editor's semantic attributed string back to markdown.
///
/// Punctuation the user typed is escaped so it round-trips as literal text —
/// typing `*hello*` stores `\*hello\*` and never becomes bold. Formatting
/// only ever comes from the semantic attributes.
struct RichTextToMarkdown {
    func markdown(from attributed: NSAttributedString) -> String {
        let text = attributed.string as NSString
        var paragraphRanges: [NSRange] = []
        var location = 0
        while location < text.length {
            let range = text.paragraphRange(for: NSRange(location: location, length: 0))
            paragraphRanges.append(range)
            location = NSMaxRange(range)
            if range.length == 0 { break }
        }
        if text.length == 0 {
            return ""
        }

        struct Block {
            let style: BlockStyle
            let range: NSRange
            let contentRange: NSRange
        }

        let blocks: [Block] = paragraphRanges.map { range in
            var contentLength = range.length
            if contentLength > 0, text.character(at: NSMaxRange(range) - 1) == 0x0A {
                contentLength -= 1
            }
            let style = attributed.blockStyle(at: range.location)
            return Block(
                style: style,
                range: range,
                contentRange: NSRange(location: range.location, length: contentLength)
            )
        }

        var output: [String] = []
        var index = 0
        while index < blocks.count {
            let block = blocks[index]

            switch block.style {
            case .code:
                // Merge consecutive code paragraphs into one fence.
                var lines: [String] = []
                while index < blocks.count, blocks[index].style == .code {
                    lines.append(text.substring(with: blocks[index].contentRange))
                    index += 1
                }
                let fence = fenceFor(lines: lines)
                output.append(fence + "\n" + lines.joined(separator: "\n") + "\n" + fence)
                continue

            case .numbered:
                var item = 1
                var listLines: [String] = []
                while index < blocks.count, blocks[index].style == .numbered {
                    let content = inlineMarkdown(in: blocks[index].contentRange, of: attributed)
                    listLines.append("\(item). \(content)")
                    item += 1
                    index += 1
                }
                output.append(listLines.joined(separator: "\n"))
                continue

            case .bullet:
                var listLines: [String] = []
                while index < blocks.count, blocks[index].style == .bullet {
                    let content = inlineMarkdown(in: blocks[index].contentRange, of: attributed)
                    listLines.append("- \(content)")
                    index += 1
                }
                output.append(listLines.joined(separator: "\n"))
                continue

            case .body:
                let content = inlineMarkdown(in: block.contentRange, of: attributed)
                output.append(content.isEmpty ? MarkdownToRichText.blankLineMarker : content)

            case .quote:
                let content = inlineMarkdown(in: block.contentRange, of: attributed)
                output.append("> " + content)

            case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6:
                let level = block.style.headingLevel ?? 1
                let content = inlineMarkdown(in: block.contentRange, of: attributed)
                output.append(String(repeating: "#", count: level) + " " + content)
            }

            index += 1
        }

        return output.joined(separator: "\n\n")
    }

    // MARK: - Inline runs

    private struct Run {
        var text: String
        var traits: InlineTraits
        var link: String?
    }

    private func inlineMarkdown(in range: NSRange, of attributed: NSAttributedString) -> String {
        guard range.length > 0 else { return "" }

        var runs: [Run] = []
        attributed.enumerateAttributes(in: range, options: []) { attrs, runRange, _ in
            let text = (attributed.string as NSString).substring(with: runRange)
            let traits = attrs.inlineTraits
            let link = attrs[.writeLink] as? String
            if var last = runs.last, last.traits == traits, last.link == link {
                last.text += text
                runs[runs.count - 1] = last
            } else {
                runs.append(Run(text: text, traits: traits, link: link))
            }
        }

        var result = ""
        for run in runs {
            result += render(run)
        }
        return finishLine(result)
    }

    private func render(_ run: Run) -> String {
        // Emphasis delimiters don't tolerate adjacent whitespace, so spaces
        // at the edges of a styled run are emitted outside the markers.
        let scalars = run.text
        let core = scalars.trimmingCharacters(in: .whitespaces)
        let leading = String(scalars.prefix(while: { $0 == " " || $0 == "\t" }))
        let trailing = core.isEmpty ? "" : String(scalars.reversed().prefix(while: { $0 == " " || $0 == "\t" }).reversed())

        guard !core.isEmpty else { return scalars }

        var rendered: String
        if run.traits.contains(.code) {
            rendered = renderInlineCode(core)
        } else {
            rendered = escapeInline(core)
            if run.traits.contains(.underline) { rendered = "<u>\(rendered)</u>" }
            if run.traits.contains(.superscript) { rendered = "<sup>\(rendered)</sup>" }
            if run.traits.contains(.subscriptText) { rendered = "<sub>\(rendered)</sub>" }
            if run.traits.contains(.italic) { rendered = "*\(rendered)*" }
            if run.traits.contains(.bold) { rendered = "**\(rendered)**" }
            if run.traits.contains(.strikethrough) { rendered = "~~\(rendered)~~" }
        }

        if let link = run.link, !link.isEmpty {
            rendered = "[\(rendered)](\(link))"
        }

        return leading + rendered + trailing
    }

    private func renderInlineCode(_ text: String) -> String {
        var fence = "`"
        while text.contains(fence) { fence += "`" }
        let needsPadding = text.hasPrefix("`") || text.hasSuffix("`")
        let padding = needsPadding ? " " : ""
        return fence + padding + text + padding + fence
    }

    private func fenceFor(lines: [String]) -> String {
        var fence = "```"
        while lines.contains(where: { $0.contains(fence) }) { fence += "`" }
        return fence
    }

    // MARK: - Escaping

    /// Characters that can start or end inline formatting anywhere in a line.
    private static let alwaysEscaped: Set<Character> = ["\\", "`", "*", "_", "~", "[", "]", "<", "&"]

    private func escapeInline(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count + 8)
        for character in text {
            if character == "\u{2028}" {
                // Hard line break within a paragraph.
                result += "<br>"
            } else if Self.alwaysEscaped.contains(character) {
                result += "\\\(character)"
            } else {
                result.append(character)
            }
        }
        return result
    }

    /// Defuses block-level syntax at the start of a serialized line and
    /// protects leading whitespace from becoming an indented code block.
    private func finishLine(_ line: String) -> String {
        guard let first = line.first else { return line }

        if first == " " || first == "\t" {
            return "&#x20;" + line.dropFirst()
        }

        switch first {
        case "#", ">", "-", "+", "=":
            return "\\" + line
        default:
            break
        }

        // "1. " or "1) " would parse as an ordered list.
        let digits = line.prefix(while: \.isNumber)
        if !digits.isEmpty, digits.count < line.count {
            let nextIndex = line.index(line.startIndex, offsetBy: digits.count)
            let next = line[nextIndex]
            if next == "." || next == ")" {
                return String(digits) + "\\" + String(line[nextIndex...])
            }
        }

        return line
    }
}
