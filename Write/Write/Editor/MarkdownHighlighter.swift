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
        let totalLength = text.length
        guard editedRange.location <= totalLength else { return }

        let safeRange = NSRange(
            location: editedRange.location,
            length: min(editedRange.length, totalLength - editedRange.location)
        )
        let paragraphRange = text.paragraphRange(for: safeRange)
        guard NSMaxRange(paragraphRange) <= totalLength else { return }

        let paragraphText = text.substring(with: paragraphRange)
        let result = parser.parseRange(paragraphText, in: text as String as NSString, offset: paragraphRange.location)

        textStorage.beginEditing()
        textStorage.setAttributes(
            renderer.attributes(for: renderer.configuration.paragraph),
            range: paragraphRange
        )
        for node in result.nodes {
            renderer.safeApplyBlock(node, to: textStorage)
        }
        renderer.applyDelimiters(result.delimiterRanges, to: textStorage)
        textStorage.endEditing()
    }
}
