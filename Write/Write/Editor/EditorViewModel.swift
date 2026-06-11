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
    /// All selection ranges — macOS supports ⌘-click discontiguous
    /// selection, so formatting applies to every range at once.
    var savedSelectedRanges: [NSRange] = [NSRange(location: 0, length: 0)]
    var zoomScale: CGFloat = 1.0

    // MARK: - Floating UI visibility (View menu toggles, persisted)

    var showsNavigator = EditorViewModel.uiDefault("write.ui.showsNavigator", false) {
        didSet { UserDefaults.standard.set(showsNavigator, forKey: "write.ui.showsNavigator") }
    }
    var showsFormattingBar = EditorViewModel.uiDefault("write.ui.showsFormattingBar", true) {
        didSet { UserDefaults.standard.set(showsFormattingBar, forKey: "write.ui.showsFormattingBar") }
    }
    var showsStatsChip = EditorViewModel.uiDefault("write.ui.showsStatsChip", true) {
        didSet { UserDefaults.standard.set(showsStatsChip, forKey: "write.ui.showsStatsChip") }
    }

    private static func uiDefault(_ key: String, _ fallback: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
    }

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
        selectionDidChange(ranges: [range])
    }

    func selectionDidChange(ranges: [NSRange]) {
        savedSelectedRanges = ranges.isEmpty ? [NSRange(location: 0, length: 0)] : ranges
        let range = savedSelectedRanges[0]
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
        let text = textStorage.string as NSString
        let ranges = savedSelectedRanges.filter { $0.length > 0 && NSMaxRange($0) <= text.length }

        if ranges.isEmpty {
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

        // Add the trait if any part of any selection lacks it; remove it
        // only when every selection already has it.
        var shouldAdd = false
        for range in ranges {
            textStorage.enumerateAttribute(.writeInlineTraits, in: range, options: []) { value, _, stop in
                let traits = InlineTraits(rawValue: (value as? NSNumber)?.intValue ?? 0)
                if !traits.contains(trait) {
                    shouldAdd = true
                    stop.pointee = true
                }
            }
            if shouldAdd { break }
        }

        performAttributeEdit(in: ranges) { storage in
            for range in ranges {
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
        }

        selectionDidChange(ranges: savedSelectedRanges)
    }

    // MARK: - Block formatting

    func setBlockStyle(_ style: BlockStyle) {
        guard let textStorage = textContentStorage.textStorage else { return }
        let paragraphRanges = mergedParagraphRanges(
            for: savedSelectedRanges, in: textStorage.string as NSString
        ).filter { $0.length > 0 }

        guard !paragraphRanges.isEmpty else {
            // Empty document or trailing empty paragraph: set typing attributes.
            activeBlockStyle = style
            updateTypingAttributes(blockStyle: style, traits: activeTraits)
            return
        }

        performAttributeEdit(in: paragraphRanges) { storage in
            for paragraphRange in paragraphRanges {
                self.setBlockStyleAttribute(style, paragraphRange: paragraphRange, in: storage)
                self.styler.applyStyles(to: storage, in: paragraphRange)
            }
        }

        activeBlockStyle = style
        updateTypingAttributes(blockStyle: style, traits: activeTraits)
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

        performAttributeEdit(in: [paragraphRange]) { storage in
            self.setBlockStyleAttribute(style, paragraphRange: paragraphRange, in: storage)
            self.styler.applyStyles(to: storage, in: paragraphRange)
        }

        activeBlockStyle = style
        updateTypingAttributes(blockStyle: style, traits: activeTraits)
    }

    /// Paragraph ranges covering every selection, merged so overlapping
    /// selections in the same paragraph aren't styled twice.
    private func mergedParagraphRanges(for ranges: [NSRange], in text: NSString) -> [NSRange] {
        let paragraphRanges = ranges.map { range -> NSRange in
            let location = min(max(0, range.location), text.length)
            let length = min(max(0, range.length), text.length - location)
            return text.paragraphRange(for: NSRange(location: location, length: length))
        }
        .sorted { $0.location < $1.location }

        var merged: [NSRange] = []
        for range in paragraphRanges {
            if let last = merged.last, NSMaxRange(last) >= range.location {
                merged[merged.count - 1] = NSUnionRange(last, range)
            } else {
                merged.append(range)
            }
        }
        return merged
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

    private func performAttributeEdit(in ranges: [NSRange], _ edit: (NSTextStorage) -> Void) {
        guard let textStorage = textContentStorage.textStorage, !ranges.isEmpty else { return }

        #if os(macOS)
        if let textView = nativeTextView {
            // Attribute-only change: registers undo with the text view.
            let rangeValues = ranges.map { NSValue(range: $0) }
            guard textView.shouldChangeText(inRanges: rangeValues, replacementStrings: nil) else { return }
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
        let snapshots = ranges.map { ($0, textStorage.attributedSubstring(from: $0)) }
        textStorage.beginEditing()
        edit(textStorage)
        textStorage.endEditing()

        if let undoManager = nativeTextView?.undoManager {
            undoManager.registerUndo(withTarget: self) { target in
                target.performAttributeEdit(in: ranges) { storage in
                    for (range, before) in snapshots {
                        storage.replaceCharacters(in: range, with: before)
                    }
                }
                target.selectionDidChange(ranges: target.savedSelectedRanges)
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

    // MARK: - Statistics

    /// Live document statistics for the stats panel. Reading `markdown`
    /// ties this to the observation system so views refresh on each edit.
    var statistics: DocumentStatistics {
        _ = markdown
        return .compute(from: textContentStorage.textStorage?.string ?? "")
    }

    // MARK: - Outline

    /// Heading outline for the navigator sidebar.
    var outline: [OutlineItem] {
        _ = markdown
        guard let textStorage = textContentStorage.textStorage else { return [] }
        let text = textStorage.string as NSString

        // Collect every paragraph with its style first, so each heading can
        // pull its section's opening words for the tooltip.
        var paragraphs: [(range: NSRange, style: BlockStyle, content: String)] = []
        var location = 0
        while location < text.length {
            let paragraph = text.paragraphRange(for: NSRange(location: location, length: 0))
            var contentLength = paragraph.length
            if contentLength > 0, text.character(at: NSMaxRange(paragraph) - 1) == 0x0A {
                contentLength -= 1
            }
            let content = text.substring(
                with: NSRange(location: paragraph.location, length: contentLength)
            )
            paragraphs.append((paragraph, textStorage.blockStyle(at: paragraph.location), content))
            location = NSMaxRange(paragraph)
            if paragraph.length == 0 { break }
        }

        var items: [OutlineItem] = []
        for (index, paragraph) in paragraphs.enumerated() {
            guard let level = paragraph.style.headingLevel else { continue }

            var previewWords: [String] = []
            for following in paragraphs[(index + 1)...] {
                guard following.style.headingLevel == nil else { break }
                previewWords.append(contentsOf: following.content.split(separator: " ").map(String.init))
                if previewWords.count >= 12 { break }
            }
            let preview = previewWords.prefix(12).joined(separator: " ")

            let title = paragraph.content.trimmingCharacters(in: .whitespaces)
            items.append(OutlineItem(
                id: paragraph.range.location,
                level: level,
                title: title.isEmpty ? "Untitled" : title,
                preview: preview.isEmpty ? "Empty section" : preview + "…",
                paragraphRange: paragraph.range
            ))
        }
        return items
    }

    /// Scrolls so the heading sits about three lines from the top, and
    /// places the caret on it.
    func scrollToHeading(at paragraphRange: NSRange) {
        let contentStorage = textContentStorage
        let documentStart = contentStorage.documentRange.location
        guard let target = contentStorage.location(documentStart, offsetBy: paragraphRange.location),
              let layoutEnd = contentStorage.location(target, offsetBy: max(paragraphRange.length, 1)),
              let layoutRange = NSTextRange(location: documentStart, end: layoutEnd)
        else { return }

        textLayoutManager.ensureLayout(for: layoutRange)
        guard let fragment = textLayoutManager.textLayoutFragment(for: target) else { return }

        let fragmentY = fragment.layoutFragmentFrame.minY
        let bodyLineHeight = styleStore.configuration.paragraph.fontSize * zoomScale * 1.4
        let headroom = bodyLineHeight * 3

        #if os(macOS)
        guard let textView = nativeTextView, let scrollView = textView.enclosingScrollView else { return }
        let maxScroll = max(0, textView.frame.height - scrollView.contentView.bounds.height)
        let targetY = min(max(0, fragmentY + textView.textContainerOrigin.y - headroom), maxScroll)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            scrollView.contentView.animator().setBoundsOrigin(
                NSPoint(x: scrollView.contentView.bounds.origin.x, y: targetY)
            )
        } completionHandler: {
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        textView.setSelectedRange(NSRange(location: paragraphRange.location, length: 0))
        textView.window?.makeFirstResponder(textView)
        #else
        guard let textView = nativeTextView else { return }
        let adjusted = textView.adjustedContentInset
        let maxOffset = max(
            -adjusted.top,
            textView.contentSize.height + adjusted.bottom - textView.bounds.height
        )
        let targetY = min(
            max(-adjusted.top, fragmentY + textView.textContainerInset.top - headroom - adjusted.top),
            maxOffset
        )
        textView.setContentOffset(CGPoint(x: 0, y: targetY), animated: true)
        textView.selectedRange = NSRange(location: paragraphRange.location, length: 0)
        #endif
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
