#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SwiftUI

enum ExportFormat: String, Identifiable {
    case pdf
    case docx

    var id: String { rawValue }
}

@Observable
final class EditorViewModel {
    let textContentStorage: NSTextContentStorage
    let textLayoutManager: NSTextLayoutManager
    let textContainer: NSTextContainer

    let styleStore: StyleStore

    weak var nativeTextView: NativeTextView?
    var savedSelectedRange = NSRange(location: 0, length: 0)
    var zoomScale: CGFloat = 1.0

    /// Serialized markdown, kept in sync with the text storage.
    private(set) var markdown: String

    /// Formatting state at the insertion point, reflected by toolbars.
    private(set) var activeTraits: InlineTraits = []
    private(set) var activeBlockStyle: BlockStyle = .body

    /// Set by menu commands; observed by the editor view to present an exporter.
    var pendingExport: ExportFormat?

    private let serializer = RichTextToMarkdown()

    var styler: RichTextStyler {
        RichTextStyler(configuration: styleStore.configuration, zoomScale: zoomScale)
    }

    init(markdown: String = "", styleStore: StyleStore = .shared) {
        self.markdown = markdown
        self.styleStore = styleStore

        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true

        let layoutManager = NSTextLayoutManager()
        layoutManager.textContainer = container

        let contentStorage = NSTextContentStorage()
        contentStorage.addTextLayoutManager(layoutManager)

        self.textContainer = container
        self.textLayoutManager = layoutManager
        self.textContentStorage = contentStorage

        setupInitialContent()
    }

    private func setupInitialContent() {
        guard let textStorage = textContentStorage.textStorage else { return }
        let content = MarkdownToRichText().attributedString(from: markdown)
        styler.applyStyles(to: content)
        textStorage.setAttributedString(content)
    }

    // MARK: - Edits

    /// Called after every text change. Restyles the affected paragraphs and
    /// re-serializes the document.
    func handleTextChange(editedRange: NSRange, insertedNewline: Bool = false) {
        guard let textStorage = textContentStorage.textStorage else { return }

        normalizeAttributes(around: editedRange, in: textStorage)
        if insertedNewline {
            exitHeadingAfterReturn(in: textStorage)
        }

        let text = textStorage.string as NSString
        let safeLocation = min(max(0, editedRange.location), text.length)
        let safeRange = NSRange(
            location: safeLocation,
            length: min(editedRange.length, text.length - safeLocation)
        )
        textStorage.beginEditing()
        styler.applyStyles(to: textStorage, in: safeRange)
        textStorage.endEditing()

        serialize()
    }

    /// Gives freshly inserted attribute-less characters (e.g. pasted text)
    /// the surrounding block style.
    private func normalizeAttributes(around editedRange: NSRange, in textStorage: NSTextStorage) {
        let text = textStorage.string as NSString
        guard text.length > 0 else { return }

        let location = min(max(0, editedRange.location), text.length)
        let length = min(editedRange.length, text.length - location)
        let paragraphRange = text.paragraphRange(for: NSRange(location: location, length: length))

        textStorage.enumerateAttribute(.writeBlockStyle, in: paragraphRange, options: []) { value, range, _ in
            guard value == nil else { return }
            let fallback = range.location > 0
                ? textStorage.blockStyle(at: range.location - 1)
                : activeBlockStyle
            textStorage.addAttribute(.writeBlockStyle, value: fallback.rawValue, range: range)
        }
    }

    /// Return at the end of a heading starts a body paragraph, like Notion.
    /// (Return in the middle of a heading still splits it into two headings.)
    private func exitHeadingAfterReturn(in textStorage: NSTextStorage) {
        let text = textStorage.string as NSString
        let cursor = min(savedSelectedRange.location, text.length)
        let cursorParagraph = text.paragraphRange(for: NSRange(location: cursor, length: 0))
        guard cursorParagraph.location > 0,
              paragraphContentLength(of: cursorParagraph, in: text) == 0 else { return }

        let previousParagraph = text.paragraphRange(
            for: NSRange(location: cursorParagraph.location - 1, length: 0)
        )
        guard textStorage.blockStyle(at: previousParagraph.location).headingLevel != nil else { return }

        if cursorParagraph.length > 0 {
            setBlockStyleAttribute(.body, paragraphRange: cursorParagraph, in: textStorage)
        }
        activeBlockStyle = .body
        updateTypingAttributes(blockStyle: .body, traits: activeTraits)
    }

    private func paragraphContentLength(of paragraph: NSRange, in text: NSString) -> Int {
        var length = paragraph.length
        if length > 0, text.character(at: NSMaxRange(paragraph) - 1) == 0x0A {
            length -= 1
        }
        return length
    }

    private func serialize() {
        guard let textStorage = textContentStorage.textStorage else { return }
        markdown = serializer.markdown(from: textStorage)
    }

    // MARK: - Selection

    func selectionDidChange(_ range: NSRange) {
        savedSelectedRange = range
        guard let textStorage = textContentStorage.textStorage else { return }
        let text = textStorage.string as NSString

        let location = min(range.location, text.length)
        activeBlockStyle = blockStyleForParagraph(at: location)

        if range.length > 0 {
            activeTraits = textStorage.inlineTraits(at: location)
        } else if let textView = nativeTextView {
            activeTraits = textView.typingAttributes.inlineTraits
        } else if location > 0 {
            activeTraits = textStorage.inlineTraits(at: location - 1)
        } else {
            activeTraits = []
        }
    }

    private func blockStyleForParagraph(at location: Int) -> BlockStyle {
        guard let textStorage = textContentStorage.textStorage else { return .body }
        let text = textStorage.string as NSString
        guard text.length > 0 else { return .body }
        let paragraph = text.paragraphRange(for: NSRange(location: min(location, text.length), length: 0))
        guard paragraph.length > 0 else {
            // Empty trailing paragraph: inherit from typing attributes.
            return nativeTextView?.typingAttributes.blockStyle ?? .body
        }
        return textStorage.blockStyle(at: paragraph.location)
    }

    // MARK: - Inline formatting

    func toggleBold() { toggleTrait(.bold) }
    func toggleItalic() { toggleTrait(.italic) }
    func toggleUnderline() { toggleTrait(.underline) }
    func toggleStrikethrough() { toggleTrait(.strikethrough) }
    func toggleInlineCode() { toggleTrait(.code) }
    func toggleSuperscript() { toggleTrait(.superscript, removing: .subscriptText) }
    func toggleSubscript() { toggleTrait(.subscriptText, removing: .superscript) }

    func toggleTrait(_ trait: InlineTraits, removing conflicting: InlineTraits = []) {
        guard let textStorage = textContentStorage.textStorage else { return }
        let range = savedSelectedRange

        if range.length == 0 {
            // No selection: flip the trait for upcoming typing.
            var traits = activeTraits
            if traits.contains(trait) {
                traits.remove(trait)
            } else {
                traits.insert(trait)
                traits.subtract(conflicting)
            }
            activeTraits = traits
            updateTypingAttributes(blockStyle: activeBlockStyle, traits: traits)
            return
        }

        let text = textStorage.string as NSString
        guard NSMaxRange(range) <= text.length else { return }

        // Add the trait if any part of the selection lacks it; remove it
        // only when the whole selection already has it.
        var shouldAdd = false
        textStorage.enumerateAttribute(.writeInlineTraits, in: range, options: []) { value, _, stop in
            let traits = InlineTraits(rawValue: (value as? NSNumber)?.intValue ?? 0)
            if !traits.contains(trait) {
                shouldAdd = true
                stop.pointee = true
            }
        }

        performAttributeEdit(in: range) { storage in
            storage.enumerateAttribute(.writeInlineTraits, in: range, options: []) { value, runRange, _ in
                var traits = InlineTraits(rawValue: (value as? NSNumber)?.intValue ?? 0)
                if shouldAdd {
                    traits.insert(trait)
                    traits.subtract(conflicting)
                } else {
                    traits.remove(trait)
                }
                if traits.isEmpty {
                    storage.removeAttribute(.writeInlineTraits, range: runRange)
                } else {
                    storage.addAttribute(
                        .writeInlineTraits, value: NSNumber(value: traits.rawValue), range: runRange
                    )
                }
            }
            self.styler.applyStyles(to: storage, in: range)
        }

        selectionDidChange(range)
    }

    // MARK: - Block formatting

    func setBlockStyle(_ style: BlockStyle) {
        setBlockStyle(style, forParagraphsIn: savedSelectedRange)
    }

    func setBlockStyle(_ style: BlockStyle, forParagraphsIn range: NSRange) {
        guard let textStorage = textContentStorage.textStorage else { return }
        let text = textStorage.string as NSString

        let location = min(max(0, range.location), text.length)
        let length = min(range.length, text.length - location)
        let paragraphRange = text.paragraphRange(for: NSRange(location: location, length: length))

        guard paragraphRange.length > 0 else {
            // Empty document or trailing empty paragraph: set typing attributes.
            activeBlockStyle = style
            updateTypingAttributes(blockStyle: style, traits: activeTraits)
            return
        }

        performAttributeEdit(in: paragraphRange) { storage in
            self.setBlockStyleAttribute(style, paragraphRange: paragraphRange, in: storage)
            self.styler.applyStyles(to: storage, in: paragraphRange)
        }

        activeBlockStyle = style
        updateTypingAttributes(blockStyle: style, traits: activeTraits)
    }

    private func setBlockStyleAttribute(
        _ style: BlockStyle, paragraphRange: NSRange, in storage: NSTextStorage
    ) {
        storage.addAttribute(.writeBlockStyle, value: style.rawValue, range: paragraphRange)
    }

    /// Pressing Return in an empty list item exits the list instead of
    /// inserting a newline. Returns true when the event was handled.
    func handleReturnKey() -> Bool {
        guard let textStorage = textContentStorage.textStorage,
              savedSelectedRange.length == 0 else { return false }
        let text = textStorage.string as NSString
        guard text.length > 0, savedSelectedRange.location <= text.length else { return false }

        let paragraph = text.paragraphRange(for: NSRange(location: savedSelectedRange.location, length: 0))
        let style = paragraph.length > 0 ? textStorage.blockStyle(at: paragraph.location) : activeBlockStyle
        guard style.isList || style == .quote,
              paragraphContentLength(of: paragraph, in: text) == 0 else { return false }

        setBlockStyle(.body, forParagraphsIn: paragraph)
        return true
    }

    // MARK: - Undo-aware attribute edits

    private func performAttributeEdit(in range: NSRange, _ edit: (NSTextStorage) -> Void) {
        guard let textStorage = textContentStorage.textStorage else { return }

        #if os(macOS)
        if let textView = nativeTextView {
            // Attribute-only change: registers undo with the text view.
            guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
            textStorage.beginEditing()
            edit(textStorage)
            textStorage.endEditing()
            textView.didChangeText()
        } else {
            textStorage.beginEditing()
            edit(textStorage)
            textStorage.endEditing()
        }
        #else
        let before = textStorage.attributedSubstring(from: range)
        textStorage.beginEditing()
        edit(textStorage)
        textStorage.endEditing()

        if let undoManager = nativeTextView?.undoManager {
            undoManager.registerUndo(withTarget: self) { target in
                target.performAttributeEdit(in: range) { storage in
                    storage.replaceCharacters(in: range, with: before)
                }
                target.selectionDidChange(target.savedSelectedRange)
            }
            undoManager.setActionName("Formatting")
        }
        #endif

        serialize()
    }

    private func updateTypingAttributes(blockStyle: BlockStyle, traits: InlineTraits) {
        guard let textView = nativeTextView else { return }
        textView.typingAttributes = styler.typingAttributes(blockStyle: blockStyle, traits: traits)
    }

    // MARK: - Style refresh & zoom

    func refreshStyle() {
        guard let textStorage = textContentStorage.textStorage else { return }
        textStorage.beginEditing()
        styler.applyStyles(to: textStorage)
        textStorage.endEditing()
        updateTypingAttributes(blockStyle: activeBlockStyle, traits: activeTraits)
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

    // MARK: - Export

    func exportData(for format: ExportFormat) -> Data? {
        guard let textStorage = textContentStorage.textStorage else { return nil }
        let content = NSMutableAttributedString(attributedString: textStorage)
        switch format {
        case .pdf:
            return PDFExporter(configuration: styleStore.configuration).pdfData(from: content)
        case .docx:
            return DocxExporter(configuration: styleStore.configuration).docxData(from: content)
        }
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
