#if os(macOS)
import AppKit
#else
import UIKit
#endif

final class MarkdownHighlighter: NSObject, NSTextContentStorageDelegate {
    let parser: MarkdownParser
    var renderer: AttributedStringRenderer

    init(parser: MarkdownParser, renderer: AttributedStringRenderer) {
        self.parser = parser
        self.renderer = renderer
        super.init()
    }

    func highlightAll(in textStorage: NSTextStorage) {
        let text = textStorage.string
        let result = parser.parse(text)
        let fullRange = NSRange(location: 0, length: (text as NSString).length)

        textStorage.beginEditing()
        textStorage.setAttributes(renderer.attributes(for: renderer.configuration.paragraph), range: fullRange)
        for node in result.nodes {
            renderer.applyBlock(node, to: textStorage)
        }
        renderer.applyDelimiters(result.delimiterRanges, to: textStorage)
        textStorage.endEditing()
    }

    func highlightRange(_ editedRange: NSRange, in textStorage: NSTextStorage) {
        let text = textStorage.string as NSString
        let paragraphRange = text.paragraphRange(for: editedRange)
        let paragraphText = text.substring(with: paragraphRange)
        let result = parser.parseRange(paragraphText, in: text, offset: paragraphRange.location)

        textStorage.beginEditing()
        textStorage.setAttributes(
            renderer.attributes(for: renderer.configuration.paragraph),
            range: paragraphRange
        )
        for node in result.nodes {
            renderer.applyBlock(node, to: textStorage)
        }
        renderer.applyDelimiters(result.delimiterRanges, to: textStorage)
        textStorage.endEditing()
    }
}
