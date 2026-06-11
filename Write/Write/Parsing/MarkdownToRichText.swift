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

    /// Sentinel characters wrapping citation placeholder tokens inserted
    /// during pre-processing. Private-use Unicode characters.
    private static let citationSentinel = "\u{F8FF}"

    /// Pre-processing result: modified source with citations replaced by
    /// placeholder tokens, and a map from token index to parsed refs.
    private struct PreprocessResult {
        var source: String
        var citations: [Int: [CitationRef]]
    }

    /// Replace unescaped `[@…]` citation spans in the raw markdown source with
    /// placeholder tokens so swift-markdown never sees the brackets.
    /// Only matches `[@` that is NOT preceded by `\` (backslash).
    private func preprocessCitations(_ source: String) -> PreprocessResult {
        var result = PreprocessResult(source: source, citations: [:])
        // Regex: a `[` NOT preceded by `\`, followed by `@`, then non-] non-newline chars, then `]`
        guard let regex = try? NSRegularExpression(
            pattern: #"(?<!\\)\[@[^\]\n]+\]"#,
            options: []
        ) else { return result }

        let nsSource = source as NSString
        let matches = regex.matches(
            in: source,
            options: [],
            range: NSRange(location: 0, length: nsSource.length)
        )

        guard !matches.isEmpty else { return result }

        // Walk backwards so ranges stay valid as we substitute.
        var citations: [Int: [CitationRef]] = [:]
        var modified = source
        var index = matches.count - 1
        while index >= 0 {
            let match = matches[index]
            let matchRange = Range(match.range, in: modified)!
            let matchString = String(modified[matchRange])
            // Strip outer `[` and `]`
            let inner = String(matchString.dropFirst().dropLast()) // "@key, p. 31" or "@a; @b"
            let refs = parseCitationInner(inner)
            let tokenIndex = index
            citations[tokenIndex] = refs
            let token = "\(Self.citationSentinel)CITE\(tokenIndex)\(Self.citationSentinel)"
            modified.replaceSubrange(matchRange, with: token)
            index -= 1
        }
        result.source = modified
        result.citations = citations
        return result
    }

    /// Parse the inside of a `[@…]` group (the part between `[` and `]`).
    /// Handles multi-cite: `@a; @b, p. 2` → two CitationRef values.
    private func parseCitationInner(_ inner: String) -> [CitationRef] {
        // Split on `;` (but not inside a key)
        let parts = inner.components(separatedBy: ";")
        return parts.compactMap { part -> CitationRef? in
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("@") else { return nil }
            let body = String(trimmed.dropFirst()) // "key" or "key, p. 31"
            // Split on first comma
            let commaIdx = body.firstIndex(of: ",")
            if let commaIdx {
                let itemID = String(body[body.startIndex..<commaIdx])
                    .trimmingCharacters(in: .whitespaces)
                let locatorPart = String(body[body.index(after: commaIdx)...])
                    .trimmingCharacters(in: .whitespaces)
                let (label, locator) = parseLocator(locatorPart)
                return CitationRef(itemID: itemID, locator: locator, label: label)
            } else {
                return CitationRef(itemID: body.trimmingCharacters(in: .whitespaces),
                                   locator: nil, label: nil)
            }
        }
    }

    /// Parse a locator string like `p. 31`, `pp. 31-33`, `chap. 2`, etc.
    /// Returns `(label, locator)` where label is the CSL term.
    private func parseLocator(_ text: String) -> (label: String, locator: String) {
        let prefixes: [(prefix: String, label: String)] = [
            ("pp. ", "page"),
            ("pp.", "page"),
            ("page ", "page"),
            ("pages ", "page"),
            ("p. ", "page"),
            ("p.", "page"),
            ("chap. ", "chapter"),
            ("chap.", "chapter"),
            ("chapter ", "chapter"),
            ("sec. ", "section"),
            ("sec.", "section"),
            ("section ", "section"),
        ]
        for (prefix, label) in prefixes {
            if text.lowercased().hasPrefix(prefix.lowercased()) {
                let locator = String(text.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespaces)
                return (label, locator)
            }
        }
        // Unknown prefix: use whole string as locator, default label = "page"
        return ("page", text)
    }

    func attributedString(from markdown: String) -> NSMutableAttributedString {
        let preprocessed = preprocessCitations(markdown)
        let document = Document(parsing: preprocessed.source, options: [])
        let result = NSMutableAttributedString()
        var blocks: [NSAttributedString] = []
        var context = ParseContext(citations: preprocessed.citations)

        for child in document.children {
            blocks.append(contentsOf: convertBlock(child, context: &context))
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

    // MARK: - Parse context

    private struct ParseContext {
        /// Citation token map from pre-processing.
        var citations: [Int: [CitationRef]]
        /// Whether we are currently inside a bibliography region.
        var inBibliography: Bool = false
    }

    // MARK: - Blocks

    private func convertBlock(_ markup: any Markup, context: inout ParseContext) -> [NSAttributedString] {
        switch markup {
        case let heading as Heading:
            let block = inlineContent(of: heading, blockStyle: .heading(level: heading.level),
                                      context: &context)
            if context.inBibliography {
                return [addBibliographyMark(block)]
            }
            return [block]

        case let paragraph as Paragraph:
            let block = inlineContent(of: paragraph, blockStyle: .body, context: &context)
            if context.inBibliography {
                return [addBibliographyMark(block)]
            }
            return [block]

        case let blockquote as BlockQuote:
            return blockquote.children.flatMap { child -> [NSAttributedString] in
                if let paragraph = child as? Paragraph {
                    let block = inlineContent(of: paragraph, blockStyle: .quote, context: &context)
                    return [context.inBibliography ? addBibliographyMark(block) : block]
                }
                return convertBlock(child, context: &context).map {
                    context.inBibliography ? addBibliographyMark(restyled($0, to: .quote)) : restyled($0, to: .quote)
                }
            }

        case let codeBlock as CodeBlock:
            var code = codeBlock.code
            if code.hasSuffix("\n") { code.removeLast() }
            return code.components(separatedBy: "\n").map { line in
                let block = NSAttributedString(string: line, attributes: [
                    .writeBlockStyle: BlockStyle.code.rawValue,
                ])
                return context.inBibliography ? addBibliographyMark(block) : block
            }

        case let list as UnorderedList:
            return list.listItems.flatMap { listParagraphs(of: $0, blockStyle: .bullet,
                                                            context: &context) }

        case let list as OrderedList:
            return list.listItems.flatMap { listParagraphs(of: $0, blockStyle: .numbered,
                                                            context: &context) }

        case is ThematicBreak:
            let block = NSAttributedString(string: "---", attributes: [
                .writeBlockStyle: BlockStyle.body.rawValue,
            ])
            return [context.inBibliography ? addBibliographyMark(block) : block]

        case let html as HTMLBlock:
            let content = html.rawHTML.trimmingCharacters(in: .whitespacesAndNewlines)

            // Bibliography region markers — handle BEFORE the generic comment rule.
            if content == "<!-- references:begin -->" {
                context.inBibliography = true
                return []  // No output paragraph for the marker itself.
            }
            if content == "<!-- references:end -->" {
                context.inBibliography = false
                return []  // No output paragraph for the marker itself.
            }

            if content.hasPrefix("<!--"), content.hasSuffix("-->") {
                // Blank-paragraph marker (or any comment): an empty paragraph.
                let block = NSAttributedString(string: "", attributes: [
                    .writeBlockStyle: BlockStyle.body.rawValue,
                ])
                return [context.inBibliography ? addBibliographyMark(block) : block]
            }
            let block = NSAttributedString(string: content, attributes: [
                .writeBlockStyle: BlockStyle.body.rawValue,
            ])
            return [context.inBibliography ? addBibliographyMark(block) : block]

        default:
            // Unknown blocks (tables, etc.) degrade to their plain text.
            let text = markup.format().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return [] }
            let block = NSAttributedString(string: text, attributes: [
                .writeBlockStyle: BlockStyle.body.rawValue,
            ])
            return [context.inBibliography ? addBibliographyMark(block) : block]
        }
    }

    private func addBibliographyMark(_ string: NSAttributedString) -> NSAttributedString {
        let copy = NSMutableAttributedString(attributedString: string)
        copy.addAttribute(
            .writeBibliography, value: NSNumber(true),
            range: NSRange(location: 0, length: copy.length)
        )
        return copy
    }

    private func listParagraphs(of item: ListItem, blockStyle: BlockStyle,
                                 context: inout ParseContext) -> [NSAttributedString] {
        item.children.flatMap { child -> [NSAttributedString] in
            if let paragraph = child as? Paragraph {
                let block = inlineContent(of: paragraph, blockStyle: blockStyle, context: &context)
                return [context.inBibliography ? addBibliographyMark(block) : block]
            }
            // Nested lists and other blocks flatten to the same level for now.
            return convertBlock(child, context: &context)
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

    private func inlineContent(of container: some Markup, blockStyle: BlockStyle,
                                context: inout ParseContext) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var state = InlineState()
        for child in container.children {
            appendInline(child, to: result, blockStyle: blockStyle, state: &state,
                         context: &context)
        }
        return result
    }

    private func appendInline(
        _ markup: any Markup,
        to result: NSMutableAttributedString,
        blockStyle: BlockStyle,
        state: inout InlineState,
        context: inout ParseContext
    ) {
        switch markup {
        case let text as Markdown.Text:
            appendText(text.string, to: result, blockStyle: blockStyle, state: state,
                       context: &context)

        case let strong as Strong:
            var inner = state
            inner.traits.insert(.bold)
            for child in strong.children {
                appendInline(child, to: result, blockStyle: blockStyle, state: &inner,
                             context: &context)
            }
            state.htmlTraits = inner.htmlTraits

        case let emphasis as Emphasis:
            var inner = state
            inner.traits.insert(.italic)
            for child in emphasis.children {
                appendInline(child, to: result, blockStyle: blockStyle, state: &inner,
                             context: &context)
            }
            state.htmlTraits = inner.htmlTraits

        case let strikethrough as Strikethrough:
            var inner = state
            inner.traits.insert(.strikethrough)
            for child in strikethrough.children {
                appendInline(child, to: result, blockStyle: blockStyle, state: &inner,
                             context: &context)
            }
            state.htmlTraits = inner.htmlTraits

        case let code as InlineCode:
            var codeState = state
            codeState.traits.insert(.code)
            appendText(code.code, to: result, blockStyle: blockStyle, state: codeState,
                       context: &context)

        case let link as Markdown.Link:
            var inner = state
            inner.link = link.destination
            for child in link.children {
                appendInline(child, to: result, blockStyle: blockStyle, state: &inner,
                             context: &context)
            }
            state.htmlTraits = inner.htmlTraits

        case let image as Markdown.Image:
            // Images aren't supported yet; keep the alt text visible.
            let alt = image.children.compactMap { ($0 as? Markdown.Text)?.string }.joined()
            appendText(alt, to: result, blockStyle: blockStyle, state: state, context: &context)

        case let html as InlineHTML:
            switch html.rawHTML.lowercased() {
            case "<u>": state.htmlTraits.insert(.underline)
            case "</u>": state.htmlTraits.remove(.underline)
            case "<sup>": state.htmlTraits.insert(.superscript)
            case "</sup>": state.htmlTraits.remove(.superscript)
            case "<sub>": state.htmlTraits.insert(.subscriptText)
            case "</sub>": state.htmlTraits.remove(.subscriptText)
            case "<br>", "<br/>", "<br />":
                appendText("\u{2028}", to: result, blockStyle: blockStyle, state: state,
                           context: &context)
            default:
                appendText(html.rawHTML, to: result, blockStyle: blockStyle, state: state,
                           context: &context)
            }

        case is SoftBreak:
            appendText(" ", to: result, blockStyle: blockStyle, state: state, context: &context)

        case is LineBreak:
            appendText("\u{2028}", to: result, blockStyle: blockStyle, state: state,
                       context: &context)

        default:
            for child in markup.children {
                appendInline(child, to: result, blockStyle: blockStyle, state: &state,
                             context: &context)
            }
        }
    }

    /// Append a text run, expanding any citation placeholder tokens it contains
    /// into chip runs with `.writeCitation` attribute.
    private func appendText(
        _ text: String,
        to result: NSMutableAttributedString,
        blockStyle: BlockStyle,
        state: InlineState,
        context: inout ParseContext
    ) {
        guard !text.isEmpty else { return }

        // Fast path: no sentinel characters — plain text.
        let sentinel = Self.citationSentinel
        guard text.contains(sentinel) else {
            appendRun(text, to: result, blockStyle: blockStyle, state: state)
            return
        }

        // Slow path: split on sentinel-delimited tokens.
        // Tokens look like: \u{F8FF}CITE<n>\u{F8FF}
        var remaining = text[text.startIndex...]
        while !remaining.isEmpty {
            if let sentinelStart = remaining.range(of: sentinel) {
                // Emit text before the sentinel.
                let before = String(remaining[remaining.startIndex..<sentinelStart.lowerBound])
                if !before.isEmpty {
                    appendRun(before, to: result, blockStyle: blockStyle, state: state)
                }
                // Find the closing sentinel.
                let afterFirst = remaining[sentinelStart.upperBound...]
                if let sentinelEnd = afterFirst.range(of: sentinel) {
                    let tokenContent = String(afterFirst[afterFirst.startIndex..<sentinelEnd.lowerBound])
                    // Parse "CITE<n>"
                    if tokenContent.hasPrefix("CITE"),
                       let tokenIndex = Int(tokenContent.dropFirst(4)),
                       let refs = context.citations[tokenIndex], !refs.isEmpty {
                        appendCitationChip(refs, to: result, blockStyle: blockStyle, state: state)
                    } else {
                        // Unknown token: emit as-is (shouldn't happen).
                        appendRun(sentinel + tokenContent + sentinel, to: result,
                                  blockStyle: blockStyle, state: state)
                    }
                    remaining = remaining[sentinelEnd.upperBound...]
                } else {
                    // Malformed: no closing sentinel, emit rest as plain text.
                    appendRun(String(remaining[sentinelStart.lowerBound...]), to: result,
                              blockStyle: blockStyle, state: state)
                    break
                }
            } else {
                appendRun(String(remaining), to: result, blockStyle: blockStyle, state: state)
                break
            }
        }
    }

    /// Append a citation chip run.  Display text is a compact placeholder;
    /// the editor will replace it with live engine output at load.
    private func appendCitationChip(
        _ refs: [CitationRef],
        to result: NSMutableAttributedString,
        blockStyle: BlockStyle,
        state: InlineState
    ) {
        let firstKey = refs.first?.itemID ?? ""
        let more = refs.count > 1
        let displayText = "(\(firstKey)\(more ? " et al" : ""))"

        var attributes: [NSAttributedString.Key: Any] = [
            .writeBlockStyle: blockStyle.rawValue,
            .writeCitation: refs.encodedJSON(),
        ]
        let traits = state.traits.union(state.htmlTraits)
        if !traits.isEmpty {
            attributes[.writeInlineTraits] = NSNumber(value: traits.rawValue)
        }
        if let link = state.link {
            attributes[.writeLink] = link
        }
        result.append(NSAttributedString(string: displayText, attributes: attributes))
    }

    private func appendRun(
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
