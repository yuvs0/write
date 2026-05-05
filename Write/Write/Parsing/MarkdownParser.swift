import Foundation
import Markdown

struct ParseResult {
    let nodes: [MarkdownNode]
    let delimiterRanges: [NSRange]
}

struct MarkdownParser {
    func parse(_ text: String) -> ParseResult {
        let document = Document(parsing: text, options: [.parseBlockDirectives, .parseSymbolLinks])
        var nodes: [MarkdownNode] = []
        var delimiters: [NSRange] = []
        let sourceText = text as NSString

        for block in document.children {
            if let node = convertBlock(block, in: sourceText, delimiters: &delimiters) {
                nodes.append(node)
            }
        }

        return ParseResult(nodes: nodes, delimiterRanges: delimiters)
    }

    func parseRange(_ text: String, in fullText: NSString, offset: Int) -> ParseResult {
        let document = Document(parsing: text, options: [.parseBlockDirectives, .parseSymbolLinks])
        var nodes: [MarkdownNode] = []
        var delimiters: [NSRange] = []

        for block in document.children {
            if let node = convertBlock(block, in: fullText, offset: offset, delimiters: &delimiters) {
                nodes.append(node)
            }
        }

        return ParseResult(nodes: nodes, delimiterRanges: delimiters)
    }

    private func convertBlock(
        _ markup: any Markup,
        in sourceText: NSString,
        offset: Int = 0,
        delimiters: inout [NSRange]
    ) -> MarkdownNode? {
        let range = nsRange(for: markup, in: sourceText, offset: offset)

        switch markup {
        case let heading as Heading:
            // "# " = level+1 chars, "## " = level+2, etc.
            let delimLen = heading.level + 1
            if range.length > delimLen {
                delimiters.append(NSRange(location: range.location, length: delimLen))
            }
            let inlines = Array(heading.inlineChildren).flatMap {
                convertInline($0, in: sourceText, offset: offset, delimiters: &delimiters)
            }
            return .heading(level: heading.level, content: inlines, range: range)

        case let paragraph as Paragraph:
            let inlines = Array(paragraph.inlineChildren).flatMap {
                convertInline($0, in: sourceText, offset: offset, delimiters: &delimiters)
            }
            return .paragraph(content: inlines, range: range)

        case let blockquote as BlockQuote:
            if range.length >= 2 {
                delimiters.append(NSRange(location: range.location, length: 2))
            }
            let inlines = Array(blockquote.children)
                .compactMap { $0 as? Paragraph }
                .flatMap { Array($0.inlineChildren) }
                .flatMap { convertInline($0, in: sourceText, offset: offset, delimiters: &delimiters) }
            return .blockquote(content: inlines, range: range)

        case let codeBlock as CodeBlock:
            return .codeBlock(language: codeBlock.language, text: codeBlock.code, range: range)

        case let list as UnorderedList:
            var nodes: [MarkdownNode] = []
            for item in list.listItems {
                let itemRange = nsRange(for: item, in: sourceText, offset: offset)
                if itemRange.length >= 2 {
                    delimiters.append(NSRange(location: itemRange.location, length: 2))
                }
                let inlines = Array(item.children)
                    .compactMap { $0 as? Paragraph }
                    .flatMap { Array($0.inlineChildren) }
                    .flatMap { convertInline($0, in: sourceText, offset: offset, delimiters: &delimiters) }
                nodes.append(.listItem(ordered: false, content: inlines, range: itemRange))
            }
            return nodes.first

        case let list as OrderedList:
            var nodes: [MarkdownNode] = []
            for item in list.listItems {
                let itemRange = nsRange(for: item, in: sourceText, offset: offset)
                let inlines = Array(item.children)
                    .compactMap { $0 as? Paragraph }
                    .flatMap { Array($0.inlineChildren) }
                    .flatMap { convertInline($0, in: sourceText, offset: offset, delimiters: &delimiters) }
                nodes.append(.listItem(ordered: true, content: inlines, range: itemRange))
            }
            return nodes.first

        case is ThematicBreak:
            return .thematicBreak(range: range)

        default:
            return nil
        }
    }

    private func convertInline(
        _ markup: any Markup,
        in sourceText: NSString,
        offset: Int,
        delimiters: inout [NSRange]
    ) -> [InlineNode] {
        let range = nsRange(for: markup, in: sourceText, offset: offset)

        switch markup {
        case let text as Markdown.Text:
            return [.text(text.string, range: range)]

        case let strong as Strong:
            if range.length > 4 {
                delimiters.append(NSRange(location: range.location, length: 2))
                delimiters.append(NSRange(location: NSMaxRange(range) - 2, length: 2))
            }
            let children = Array(strong.inlineChildren).flatMap {
                convertInline($0, in: sourceText, offset: offset, delimiters: &delimiters)
            }
            return [.strong(children: children, range: range)]

        case let emphasis as Emphasis:
            if range.length > 2 {
                delimiters.append(NSRange(location: range.location, length: 1))
                delimiters.append(NSRange(location: NSMaxRange(range) - 1, length: 1))
            }
            let children = Array(emphasis.inlineChildren).flatMap {
                convertInline($0, in: sourceText, offset: offset, delimiters: &delimiters)
            }
            return [.emphasis(children: children, range: range)]

        case let strikethrough as Strikethrough:
            if range.length > 4 {
                delimiters.append(NSRange(location: range.location, length: 2))
                delimiters.append(NSRange(location: NSMaxRange(range) - 2, length: 2))
            }
            let children = Array(strikethrough.inlineChildren).flatMap {
                convertInline($0, in: sourceText, offset: offset, delimiters: &delimiters)
            }
            return [.strikethrough(children: children, range: range)]

        case let code as InlineCode:
            let delimLen = max(1, (range.length - code.code.utf16.count) / 2)
            if range.length > delimLen * 2 {
                delimiters.append(NSRange(location: range.location, length: delimLen))
                delimiters.append(NSRange(location: NSMaxRange(range) - delimLen, length: delimLen))
            }
            return [.inlineCode(code.code, range: range)]

        case let link as Markdown.Link:
            let children = Array(link.inlineChildren).flatMap {
                convertInline($0, in: sourceText, offset: offset, delimiters: &delimiters)
            }
            return [.link(destination: link.destination, children: children, range: range)]

        default:
            return Array(markup.children).flatMap {
                convertInline($0, in: sourceText, offset: offset, delimiters: &delimiters)
            }
        }
    }

    private func nsRange(for markup: any Markup, in sourceText: NSString, offset: Int) -> NSRange {
        guard let sourceRange = markup.range else {
            return NSRange(location: offset, length: 0)
        }

        let startLine = sourceRange.lowerBound.line - 1
        let startColumn = sourceRange.lowerBound.column - 1
        let endLine = sourceRange.upperBound.line - 1
        let endColumn = sourceRange.upperBound.column - 1

        let relevantText = sourceText.substring(from: offset) as NSString
        let lines = relevantText.components(separatedBy: .newlines)

        var startLocation = offset
        for i in 0..<min(startLine, lines.count) {
            startLocation += lines[i].utf16.count + 1
        }
        if startLine < lines.count {
            startLocation += min(startColumn, lines[startLine].utf16.count)
        }

        var endLocation = offset
        for i in 0..<min(endLine, lines.count) {
            endLocation += lines[i].utf16.count + 1
        }
        if endLine < lines.count {
            endLocation += min(endColumn, lines[endLine].utf16.count)
        }

        let length = max(0, endLocation - startLocation)
        let clampedLength = min(length, sourceText.length - startLocation)
        guard startLocation >= 0, startLocation <= sourceText.length, clampedLength >= 0 else {
            return NSRange(location: offset, length: 0)
        }
        return NSRange(location: startLocation, length: clampedLength)
    }
}
