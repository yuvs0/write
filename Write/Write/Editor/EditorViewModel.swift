#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SwiftUI

@Observable
final class EditorViewModel {
    let textContentStorage: NSTextContentStorage
    let textLayoutManager: NSTextLayoutManager
    let textContainer: NSTextContainer

    let styleStore: StyleStore
    let parser: MarkdownParser
    let highlighter: MarkdownHighlighter

    weak var nativeTextView: NativeTextView?
    var savedSelectedRange: NSRange = NSRange(location: 0, length: 0)
    var zoomScale: CGFloat = 1.0

    private(set) var text: String

    init(text: String = "", styleStore: StyleStore = StyleStore()) {
        self.text = text
        self.styleStore = styleStore
        self.parser = MarkdownParser()

        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true

        let layoutManager = NSTextLayoutManager()
        layoutManager.textContainer = container

        let contentStorage = NSTextContentStorage()
        contentStorage.addTextLayoutManager(layoutManager)

        self.textContainer = container
        self.textLayoutManager = layoutManager
        self.textContentStorage = contentStorage

        let renderer = AttributedStringRenderer(configuration: styleStore.configuration)
        self.highlighter = MarkdownHighlighter(parser: parser, renderer: renderer)

        setupInitialContent()
    }

    func handleTextChange(_ newText: String, editedRange: NSRange) {
        text = newText
        guard let textStorage = textContentStorage.textStorage else { return }
        highlighter.highlightRange(editedRange, in: textStorage)
    }

    func zoomIn() {
        zoomScale = min(zoomScale + 0.1, 3.0)
        refreshStyle()
    }

    func zoomOut() {
        zoomScale = max(zoomScale - 0.1, 0.5)
        refreshStyle()
    }

    func resetZoom() {
        zoomScale = 1.0
        refreshStyle()
    }

    func applyHighlighting() {
        guard let textStorage = textContentStorage.textStorage else { return }

        let currentText = textStorage.string
        let result = parser.parse(currentText)
        let renderer = AttributedStringRenderer(configuration: styleStore.configuration, zoomScale: zoomScale)
        let fullRange = NSRange(location: 0, length: (currentText as NSString).length)

        textStorage.beginEditing()
        textStorage.setAttributes(renderer.attributes(for: styleStore.configuration.paragraph), range: fullRange)
        for node in result.nodes {
            renderer.applyBlock(node, to: textStorage)
        }
        renderer.applyDelimiters(result.delimiterRanges, to: textStorage)
        textStorage.endEditing()
    }

    func refreshStyle() {
        highlighter.renderer = AttributedStringRenderer(configuration: styleStore.configuration, zoomScale: zoomScale)
        applyHighlighting()
    }

    // MARK: - Formatting commands

    func toggleBold() { toggleInlineMarker("**") }
    func toggleItalic() { toggleInlineMarker("*") }
    func toggleStrikethrough() { toggleInlineMarker("~~") }
    func toggleInlineCode() { toggleInlineMarker("`") }
    func toggleUnderline() { toggleInlineMarker("<u>", closing: "</u>") }
    func toggleSuperscript() { toggleInlineMarker("^") }
    func toggleSubscript() { toggleInlineMarker("~") }

    private func toggleInlineMarker(_ marker: String, closing: String? = nil) {
        let close = closing ?? marker

        guard let textStorage = textContentStorage.textStorage else { return }
        let range = savedSelectedRange
        guard range.length > 0 else { return }

        let text = textStorage.string as NSString
        guard NSMaxRange(range) <= text.length else { return }

        let selected = text.substring(with: range)

        let newText: String
        let newSelectionOffset: Int
        let newSelectionLength: Int

        if selected.hasPrefix(marker), selected.hasSuffix(close),
           selected.count > marker.count + close.count {
            let inner = String(selected.dropFirst(marker.count).dropLast(close.count))
            newText = inner
            newSelectionOffset = 0
            newSelectionLength = inner.utf16.count
        } else {
            newText = marker + selected + close
            newSelectionOffset = marker.utf16.count
            newSelectionLength = range.length
        }

        replaceText(in: range, with: newText)

        let newRange = NSRange(location: range.location + newSelectionOffset, length: newSelectionLength)
        savedSelectedRange = newRange
        restoreSelectionAfterEdit(newRange)
    }

    private func replaceText(in range: NSRange, with newText: String) {
        guard let textStorage = textContentStorage.textStorage else { return }

        textStorage.beginEditing()
        textStorage.replaceCharacters(in: range, with: newText)
        textStorage.endEditing()

        text = textStorage.string
        applyHighlighting()
    }

    private func restoreSelectionAfterEdit(_ range: NSRange) {
        #if os(macOS)
        guard let tv = nativeTextView else { return }
        tv.window?.makeFirstResponder(tv)
        let safeRange = NSRange(
            location: min(range.location, tv.string.utf16.count),
            length: min(range.length, max(0, tv.string.utf16.count - range.location))
        )
        tv.setSelectedRange(safeRange)
        #else
        guard let tv = nativeTextView as? UITextView,
              let start = tv.position(from: tv.beginningOfDocument, offset: range.location),
              let end = tv.position(from: start, offset: range.length),
              let textRange = tv.textRange(from: start, to: end) else { return }
        tv.selectedTextRange = textRange
        #endif
    }

    private func setupInitialContent() {
        guard let textStorage = textContentStorage.textStorage else { return }

        let renderer = AttributedStringRenderer(configuration: styleStore.configuration, zoomScale: zoomScale)
        let result = parser.parse(text)
        let attributed = renderer.attributedString(from: result, in: text as NSString)

        textStorage.setAttributedString(attributed)
    }
}

struct EditorViewModelKey: FocusedValueKey {
    typealias Value = EditorViewModel
}

extension FocusedValues {
    var editorViewModel: EditorViewModel? {
        get { self[EditorViewModelKey.self] }
        set { self[EditorViewModelKey.self] = newValue }
    }
}
