import Foundation
import Markdown

/// Converts stored markdown into an attributed string containing only the
/// visible content text, with formatting captured as semantic attributes
/// (`.writeBlockStyle`, `.writeInlineTraits`, `.writeLink`).
///
/// Markdown is purely a storage format: delimiters never appear in the
/// editor, and escaped punctuation (`\*`) comes back as literal text.
struct MarkdownToRichText {
    /// Marker block used to round-trip empty paragraphs, which plain
    /// markdown would otherwise collapse.
    static let blankLineMarker = "<!-- -->"

    func attributedString(from markdown: String) -> NSMutableAttributedString {
        let document = Document(parsing: markdown, options: [])
        let result = NSMutableAttributedString()
        var blocks: [NSAttributedString] = []

        for child in document.children {
            blocks.append(contentsOf: convertBlock(child))
        }

        for (index, block) in blocks.enumerated() {
            result.append(block)
            if index < blocks.count - 1 {
                // The newline belongs to the paragraph it terminates so the
                // block style attribute covers the whole paragraph range.
                let newline = NSMutableAttributedString(string: "\n")
                if block.length > 0 {
                    newline.setAttributes(
                        block.attributes(at: block.length - 1, effectiveRange: nil),
                        range: NSRange(location: 0, length: 1)
                    )
                } else {
                    newline.setAttributes(
                        [.writeBlockStyle: BlockStyle.body.rawValue],
                        range: NSRange(location: 0, length: 1)
                    )
                }
                result.append(newline)
            }
        }

        return result
    }

    // MARK: - Blocks

    private func convertBlock(_ markup: any Markup) -> [NSAttributedString] {
        switch markup {
        case let heading as Heading:
            return [inlineContent(of: heading, blockStyle: .heading(level: heading.level))]

        case let paragraph as Paragraph:
            return [inlineContent(of: paragraph, blockStyle: .body)]

        case let blockquote as BlockQuote:
            return blockquote.children.flatMap { child -> [NSAttributedString] in
                if let paragraph = child as? Paragraph {
                    return [inlineContent(of: paragraph, blockStyle: .quote)]
                }
                return convertBlock(child).map { restyled($0, to: .quote) }
            }

        case let codeBlock as CodeBlock:
            var code = codeBlock.code
            if code.hasSuffix("\n") { code.removeLast() }
            return code.components(separatedBy: "\n").map { line in
                NSAttributedString(string: line, attributes: [
                    .writeBlockStyle: BlockStyle.code.rawValue,
                ])
            }

        case let list as UnorderedList:
            return list.listItems.flatMap { listParagraphs(of: $0, blockStyle: .bullet) }

        case let list as OrderedList:
            return list.listItems.flatMap { listParagraphs(of: $0, blockStyle: .numbered) }

        case is ThematicBreak:
            return [NSAttributedString(string: "---", attributes: [
                .writeBlockStyle: BlockStyle.body.rawValue,
            ])]

        case let html as HTMLBlock:
            let content = html.rawHTML.trimmingCharacters(in: .whitespacesAndNewlines)
            if content.hasPrefix("<!--"), content.hasSuffix("-->") {
                // Blank-paragraph marker (or any comment): an empty paragraph.
                return [NSAttributedString(string: "", attributes: [
                    .writeBlockStyle: BlockStyle.body.rawValue,
                ])]
            }
            return [NSAttributedString(string: content, attributes: [
                .writeBlockStyle: BlockStyle.body.rawValue,
            ])]

        default:
            // Unknown blocks (tables, etc.) degrade to their plain text.
            let text = markup.format().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return [] }
            return [NSAttributedString(string: text, attributes: [
                .writeBlockStyle: BlockStyle.body.rawValue,
            ])]
        }
    }

    private func listParagraphs(of item: ListItem, blockStyle: BlockStyle) -> [NSAttributedString] {
        item.children.flatMap { child -> [NSAttributedString] in
            if let paragraph = child as? Paragraph {
                return [inlineContent(of: paragraph, blockStyle: blockStyle)]
            }
            // Nested lists and other blocks flatten to the same level for now.
            return convertBlock(child)
        }
    }

    private func restyled(_ string: NSAttributedString, to blockStyle: BlockStyle) -> NSAttributedString {
        let copy = NSMutableAttributedString(attributedString: string)
        copy.addAttribute(
            .writeBlockStyle, value: blockStyle.rawValue,
            range: NSRange(location: 0, length: copy.length)
        )
        return copy
    }

    // MARK: - Inlines

    private struct InlineState {
        var traits: InlineTraits = []
        var link: String?
        /// Traits toggled by raw HTML tags (<u>, <sup>, <sub>), which arrive
        /// as separate open/close events rather than a nested tree.
        var htmlTraits: InlineTraits = []
    }

    private func inlineContent(of container: some Markup, blockStyle: BlockStyle) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var state = InlineState()
        for child in container.children {
            appendInline(child, to: result, blockStyle: blockStyle, state: &state)
        }
        return result
    }

    private func appendInline(
        _ markup: any Markup,
        to result: NSMutableAttributedString,
        blockStyle: BlockStyle,
        state: inout InlineState
    ) {
        switch markup {
        case let text as Markdown.Text:
            append(text.string, to: result, blockStyle: blockStyle, state: state)

        case let strong as Strong:
            var inner = state
            inner.traits.insert(.bold)
            for child in strong.children {
                appendInline(child, to: result, blockStyle: blockStyle, state: &inner)
            }
            state.htmlTraits = inner.htmlTraits

        case let emphasis as Emphasis:
            var inner = state
            inner.traits.insert(.italic)
            for child in emphasis.children {
                appendInline(child, to: result, blockStyle: blockStyle, state: &inner)
            }
            state.htmlTraits = inner.htmlTraits

        case let strikethrough as Strikethrough:
            var inner = state
            inner.traits.insert(.strikethrough)
            for child in strikethrough.children {
                appendInline(child, to: result, blockStyle: blockStyle, state: &inner)
            }
            state.htmlTraits = inner.htmlTraits

        case let code as InlineCode:
            var codeState = state
            codeState.traits.insert(.code)
            append(code.code, to: result, blockStyle: blockStyle, state: codeState)

        case let link as Markdown.Link:
            var inner = state
            inner.link = link.destination
            for child in link.children {
                appendInline(child, to: result, blockStyle: blockStyle, state: &inner)
            }
            state.htmlTraits = inner.htmlTraits

        case let image as Markdown.Image:
            // Images aren't supported yet; keep the alt text visible.
            let alt = image.children.compactMap { ($0 as? Markdown.Text)?.string }.joined()
            append(alt, to: result, blockStyle: blockStyle, state: state)

        case let html as InlineHTML:
            switch html.rawHTML.lowercased() {
            case "<u>": state.htmlTraits.insert(.underline)
            case "</u>": state.htmlTraits.remove(.underline)
            case "<sup>": state.htmlTraits.insert(.superscript)
            case "</sup>": state.htmlTraits.remove(.superscript)
            case "<sub>": state.htmlTraits.insert(.subscriptText)
            case "</sub>": state.htmlTraits.remove(.subscriptText)
            case "<br>", "<br/>", "<br />":
                append("\u{2028}", to: result, blockStyle: blockStyle, state: state)
            default:
                append(html.rawHTML, to: result, blockStyle: blockStyle, state: state)
            }

        case is SoftBreak:
            append(" ", to: result, blockStyle: blockStyle, state: state)

        case is LineBreak:
            append("\u{2028}", to: result, blockStyle: blockStyle, state: state)

        default:
            for child in markup.children {
                appendInline(child, to: result, blockStyle: blockStyle, state: &state)
            }
        }
    }

    private func append(
        _ text: String,
        to result: NSMutableAttributedString,
        blockStyle: BlockStyle,
        state: InlineState
    ) {
        guard !text.isEmpty else { return }
        var attributes: [NSAttributedString.Key: Any] = [
            .writeBlockStyle: blockStyle.rawValue,
        ]
        let traits = state.traits.union(state.htmlTraits)
        if !traits.isEmpty {
            attributes[.writeInlineTraits] = NSNumber(value: traits.rawValue)
        }
        if let link = state.link {
            attributes[.writeLink] = link
        }
        result.append(NSAttributedString(string: text, attributes: attributes))
    }
}
