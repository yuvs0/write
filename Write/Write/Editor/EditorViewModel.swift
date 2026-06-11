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

    /// Per-document bibliographic sources and citation style.
    let referenceStore: ReferenceStore

    /// Owns the live citeproc engine and all citation-specific transforms.
    let citationController: CitationController

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

    // MARK: - Citation UI state (observed by the editor view)

    /// True while a ⌘↩ resolution is in flight (shows a spinner near the caret).
    var isResolvingCitation = false
    /// Set on resolution failure; the view surfaces it as a small toast/alert.
    var citationError: String?
    /// When non-nil, the editor view should present the locator popover anchored
    /// at this chip range (set right after a ⌘↩ conversion or a chip click).
    var pendingPopoverChipRange: NSRange?

    private let serializer = RichTextToMarkdown()

    var styler: RichTextStyler {
        RichTextStyler(configuration: styleStore.configuration, zoomScale: zoomScale)
    }

    init(
        markdown: String = "",
        styleStore: StyleStore = .shared,
        referencesData: Data? = nil,
        settingsData: Data? = nil
    ) {
        self.markdown = markdown
        self.styleStore = styleStore

        let store = ReferenceStore(referencesData: referencesData, settingsData: settingsData)
        self.referenceStore = store
        self.citationController = CitationController(store: store)

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

        // Chips load with placeholder display text "(key)"; re-render them
        // from the live engine. Only bother if the document actually has
        // citation content or the store carries sources.
        let hasChips = CitationController.chipRuns(in: textStorage).isEmpty == false
        let hasBibliography = CitationController.bibliographyRange(in: textStorage) != nil
        if hasChips || hasBibliography || !referenceStore.items.isEmpty {
            refreshCitations()
        }
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

    /// Guards against re-entrancy when we re-set the selection to snap it out
    /// of a chip (re-setting fires the platform selection callback again).
    private var isSnappingSelection = false

    func selectionDidChange(_ range: NSRange) {
        selectionDidChange(ranges: [range])
    }

    func selectionDidChange(ranges: [NSRange]) {
        var ranges = ranges.isEmpty ? [NSRange(location: 0, length: 0)] : ranges

        // Snap any endpoint that landed strictly inside a chip out to the chip
        // boundary, so chips behave atomically. If the snap changed anything,
        // push it back onto the text view (guarded against recursion).
        if !isSnappingSelection, let textStorage = textContentStorage.textStorage {
            let snapped = ranges.map { CitationController.snapOutOfChips($0, in: textStorage) }
            if snapped != ranges {
                ranges = snapped
                isSnappingSelection = true
                applySelectionToTextView(ranges)
                isSnappingSelection = false
            }
        }

        savedSelectedRanges = ranges
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

        // Typing right after a chip, or at the edge of the bibliography region,
        // must not inherit those attributes. Strip them from typingAttributes.
        if range.length == 0 {
            stripBoundaryTypingAttributes(at: location, in: textStorage)
        }
    }

    /// Push `ranges` back onto the native text view (used by selection snapping).
    private func applySelectionToTextView(_ ranges: [NSRange]) {
        #if os(macOS)
        guard let textView = nativeTextView else { return }
        textView.setSelectedRanges(
            ranges.map { NSValue(range: $0) }, affinity: .downstream, stillSelecting: false
        )
        #else
        guard let textView = nativeTextView else { return }
        textView.selectedRange = ranges.first ?? NSRange(location: 0, length: 0)
        #endif
    }

    /// Remove `.writeCitation` / `.writeBibliography` from the text view's
    /// typingAttributes when the caret abuts a chip or the bibliography region,
    /// so new typing never adopts those attributes.
    private func stripBoundaryTypingAttributes(at location: Int, in textStorage: NSTextStorage) {
        guard let textView = nativeTextView else { return }
        var typing = textView.typingAttributes
        var changed = false

        if typing[.writeCitation] != nil {
            // Typing never continues a chip — always strip the attribute when
            // the caret abuts one (selection snapping keeps us at boundaries).
            typing.removeValue(forKey: .writeCitation)
            changed = true
        }
        // At the outer edges of the bibliography region, escape the read-only
        // region by dropping its attribute from new typing.
        if typing[.writeBibliography] != nil,
           let region = CitationController.bibliographyRange(in: textStorage),
           location <= region.location || location >= NSMaxRange(region) {
            typing.removeValue(forKey: .writeBibliography)
            changed = true
        }
        if changed {
            textView.typingAttributes = typing
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
        scrollTo(range: paragraphRange)
    }

    /// Scrolls so `range` sits about three lines from the top, and places the
    /// caret at its start. Generalizes the heading-scroll machinery so it also
    /// serves citation jumps.
    func scrollTo(range targetRange: NSRange) {
        let paragraphRange = targetRange
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
            let references = referenceStore.items.isEmpty ? nil : ReferenceExportContext(
                items: referenceStore.items,
                styleID: referenceStore.styleID
            )
            return DocxExporter(
                configuration: styleStore.configuration,
                references: references
            ).docxData(from: content)
        }
    }

    // MARK: - Citations

    /// Refresh the engine, re-render every chip from live citeproc output,
    /// regenerate the bibliography region if present, then re-style and
    /// serialize. This is a programmatic pass — done directly on the storage,
    /// not via the undo machinery (chip text is generated, not user-authored).
    func refreshCitations() {
        guard let textStorage = textContentStorage.textStorage else { return }
        let engine = citationController.currentEngine()

        textStorage.beginEditing()
        let chipsChanged = CitationController.rerenderChips(in: textStorage, engine: engine)
        let bibChanged = CitationController.regenerateBibliography(in: textStorage, engine: engine)
        textStorage.endEditing()

        guard chipsChanged || bibChanged else { return }

        // Re-style the whole document: chip and bibliography paragraph lengths
        // may have shifted, and styling is cheap relative to a citeproc pass.
        textStorage.beginEditing()
        styler.applyStyles(to: textStorage)
        textStorage.endEditing()

        serialize()
    }

    /// Regenerate just the bibliography region (no chip pass). Used when the
    /// caller knows only sources/style changed via a path that already handled
    /// chips, or as a lightweight hook.
    func regenerateBibliographyIfPresent() {
        guard let textStorage = textContentStorage.textStorage else { return }
        let engine = citationController.currentEngine()
        textStorage.beginEditing()
        let changed = CitationController.regenerateBibliography(in: textStorage, engine: engine)
        textStorage.endEditing()
        guard changed else { return }
        textStorage.beginEditing()
        styler.applyStyles(to: textStorage)
        textStorage.endEditing()
        serialize()
    }

    /// Switch the document's citation style and restyle all chips + bibliography.
    func setCitationStyle(_ styleID: String) {
        guard styleID != referenceStore.styleID else { return }
        referenceStore.styleID = styleID
        // The style change bumps the store revision; the view layer's onChange
        // will call refreshCitations(). Call it directly too so menu-driven
        // changes take effect even if no observer is attached yet.
        refreshCitations()
    }

    // MARK: - Bibliography insertion

    /// Insert (or replace) the generated references list.
    ///
    /// - If a region already exists anywhere in the document, it is replaced in
    ///   place and `atEnd` is ignored.
    /// - Otherwise the region is inserted at the document end (`atEnd == true`)
    ///   or at the start of the caret's paragraph (`atEnd == false`), with a
    ///   blank body paragraph separating it from preceding content.
    func insertReferencesList(atEnd: Bool) {
        guard let textStorage = textContentStorage.textStorage else { return }
        let engine = citationController.currentEngine()

        // Replace in place if a region exists.
        if CitationController.bibliographyRange(in: textStorage) != nil {
            regenerateBibliographyIfPresent()
            return
        }

        let entries = engine?.bibliography() ?? []
        let region = CitationController.makeBibliographyRegion(entries: entries)

        let nsText = textStorage.string as NSString
        let insertionPoint: Int
        if atEnd || nsText.length == 0 {
            insertionPoint = nsText.length
        } else {
            let caret = min(savedSelectedRange.location, nsText.length)
            insertionPoint = nsText.paragraphRange(for: NSRange(location: caret, length: 0)).location
        }

        // Build the fragment: a blank separator paragraph (unless inserting into
        // an empty document or at the very start) + the region + a trailing
        // newline so following content stays in its own paragraph.
        let fragment = NSMutableAttributedString()
        let needsLeadingSeparator = insertionPoint > 0
        if needsLeadingSeparator {
            fragment.append(NSAttributedString(
                string: "\n", attributes: [.writeBlockStyle: BlockStyle.body.rawValue]
            ))
            fragment.append(NSAttributedString(
                string: "\n", attributes: [.writeBlockStyle: BlockStyle.body.rawValue]
            ))
        }
        fragment.append(region)
        // Trailing newline if we are not at document end, to terminate the region.
        if insertionPoint < nsText.length {
            fragment.append(NSAttributedString(
                string: "\n",
                attributes: [
                    .writeBlockStyle: BlockStyle.body.rawValue,
                    .writeBibliography: NSNumber(true),
                ]
            ))
        }

        performCitationReplacement(
            range: NSRange(location: insertionPoint, length: 0),
            with: fragment,
            actionName: "Insert References List"
        )
    }

    // MARK: - ⌘↩ citation creation

    /// Convert a URL/DOI/arXiv/ISBN token at (or just before) the caret into a
    /// citation chip. Resolves metadata off the main actor, dedupes against the
    /// store, then replaces the token with a chip on the main actor.
    func citeTokenAtCaret() {
        guard !isResolvingCitation,
              let textStorage = textContentStorage.textStorage else { return }
        let nsText = textStorage.string as NSString
        let caret = min(savedSelectedRange.location, nsText.length)
        let paragraph = nsText.paragraphRange(for: NSRange(location: caret, length: 0))
        var contentLength = paragraph.length
        if contentLength > 0, nsText.character(at: NSMaxRange(paragraph) - 1) == 0x0A {
            contentLength -= 1
        }
        let contentRange = NSRange(location: paragraph.location, length: contentLength)
        let paragraphText = nsText.substring(with: contentRange)

        guard let token = CitationController.detectToken(
            inParagraph: paragraphText, paragraphRange: contentRange, caret: caret
        ) else {
            citationError = "No link or DOI found near the cursor to cite."
            return
        }

        isResolvingCitation = true
        citationError = nil
        let tokenRange = token.range
        let input = token.input
        let resolver = MetadataResolver()

        Task { [weak self] in
            do {
                let resolved = try await resolver.resolve(input)
                await MainActor.run {
                    self?.finishCitation(resolved: resolved, input: input, tokenRange: tokenRange)
                }
            } catch {
                let reason = (error as? LocalizedError)?.errorDescription
                    ?? "Couldn't resolve the source."
                await MainActor.run {
                    self?.isResolvingCitation = false
                    self?.citationError = reason
                }
            }
        }
    }

    /// Main-actor continuation of `citeTokenAtCaret`: dedupe, insert the chip.
    private func finishCitation(
        resolved: CSLItem, input: MetadataResolver.Input, tokenRange: NSRange
    ) {
        isResolvingCitation = false
        guard let textStorage = textContentStorage.textStorage else { return }

        // Dedupe by DOI/URL, else add (which generates a citekey).
        let stored: CSLItem
        if let doi = resolved.doi, let existing = referenceStore.find(doi: doi) {
            stored = existing
        } else if let url = resolved.url, let existing = referenceStore.find(url: url) {
            stored = existing
        } else {
            stored = referenceStore.add(resolved)
        }

        // Build the chip from the live engine (placeholder if it fails).
        let refs = [CitationRef(itemID: stored.id, locator: nil, label: nil)]
        let engine = citationController.currentEngine()
        let display = engine?.inlineCitation(refs) ?? "(\(stored.id))"

        // Guard the token range against intervening edits.
        let safeRange = NSRange(
            location: min(tokenRange.location, textStorage.length),
            length: min(tokenRange.length, max(0, textStorage.length - tokenRange.location))
        )
        let chip = NSAttributedString(string: display, attributes: [
            .writeBlockStyle: textStorage.blockStyle(at: safeRange.location).rawValue,
            .writeCitation: refs.encodedJSON(),
        ])

        performCitationReplacement(range: safeRange, with: chip, actionName: "Add Citation")

        // Trigger the locator popover anchored at the new chip.
        pendingPopoverChipRange = NSRange(location: safeRange.location, length: chip.length)

        // Regenerate bibliography if present (new source may belong in it).
        regenerateBibliographyIfPresent()
    }

    // MARK: - Chip editing (popover)

    /// Apply edited refs to the chip at `range`: rewrite its `.writeCitation`
    /// JSON, re-render its text from the engine, restyle, serialize — undo-aware.
    func updateCitation(at range: NSRange, refs: [CitationRef]) {
        guard let textStorage = textContentStorage.textStorage,
              NSMaxRange(range) <= textStorage.length else { return }
        let engine = citationController.currentEngine()
        let display = engine?.inlineCitation(refs) ?? (textStorage.string as NSString).substring(with: range)
        var attrs = textStorage.attributes(at: range.location, effectiveRange: nil)
        attrs[.writeCitation] = refs.encodedJSON()
        let chip = NSAttributedString(string: display, attributes: attrs)
        performCitationReplacement(range: range, with: chip, actionName: "Edit Citation")
    }

    /// Remove the chip at `range`, deleting its characters entirely. Undo-aware.
    func removeCitation(at range: NSRange) {
        guard let textStorage = textContentStorage.textStorage,
              NSMaxRange(range) <= textStorage.length else { return }
        performCitationReplacement(
            range: range, with: NSAttributedString(string: ""), actionName: "Remove Citation"
        )
        regenerateBibliographyIfPresent()
    }

    /// The refs stored on the chip at `range`, or nil.
    func citationRefs(at range: NSRange) -> [CitationRef]? {
        guard let textStorage = textContentStorage.textStorage,
              range.location < textStorage.length else { return nil }
        return textStorage.citationRefs(at: range.location)
    }

    /// The source backing the chip at `range`'s first ref, for the popover.
    func citationSource(at range: NSRange) -> CSLItem? {
        guard let first = citationRefs(at: range)?.first else { return nil }
        return referenceStore.item(id: first.itemID)
    }

    // MARK: - Undo-aware character replacement (chips)

    /// Set while a programmatic chip replacement is running, so the platform
    /// `shouldChangeText` hook lets our own `shouldChangeText` call through
    /// without re-running interception (it would otherwise recurse).
    private(set) var isPerformingCitationEdit = false

    /// Replace `range` with `replacement`, routing through the text view so
    /// ⌘Z restores the prior characters. Restyles the touched paragraphs and
    /// serializes. Used for all chip insert/edit/remove operations.
    private func performCitationReplacement(
        range: NSRange, with replacement: NSAttributedString, actionName: String
    ) {
        guard let textStorage = textContentStorage.textStorage,
              NSMaxRange(range) <= textStorage.length else { return }

        #if os(macOS)
        if let textView = nativeTextView {
            isPerformingCitationEdit = true
            defer { isPerformingCitationEdit = false }
            guard textView.shouldChangeText(in: range, replacementString: replacement.string) else { return }
            textStorage.beginEditing()
            textStorage.replaceCharacters(in: range, with: replacement)
            textStorage.endEditing()
            textView.didChangeText()
        } else {
            textStorage.beginEditing()
            textStorage.replaceCharacters(in: range, with: replacement)
            textStorage.endEditing()
        }
        #else
        let before = textStorage.attributedSubstring(from: range)
        let newRange = NSRange(location: range.location, length: replacement.length)
        textStorage.beginEditing()
        textStorage.replaceCharacters(in: range, with: replacement)
        textStorage.endEditing()
        if let undoManager = nativeTextView?.undoManager {
            undoManager.registerUndo(withTarget: self) { target in
                target.performCitationReplacement(
                    range: newRange, with: before, actionName: actionName
                )
            }
            undoManager.setActionName(actionName)
        }
        #endif

        // Restyle the affected paragraphs and serialize.
        let touched = NSRange(location: range.location, length: replacement.length)
        let nsText = textStorage.string as NSString
        let safeLocation = min(max(0, touched.location), nsText.length)
        let safeRange = NSRange(
            location: safeLocation,
            length: min(touched.length, nsText.length - safeLocation)
        )
        textStorage.beginEditing()
        styler.applyStyles(to: textStorage, in: safeRange)
        textStorage.endEditing()

        serialize()
    }

    // MARK: - Edit interception (chip atomicity & read-only bibliography)

    /// Decision returned to the platform `shouldChangeText` hook.
    enum EditDecision {
        /// Let the text view perform the edit normally.
        case allow
        /// Block the edit entirely (read-only region).
        case reject
        /// The view model performed an adjusted edit programmatically; the hook
        /// should return false.
        case handled
    }

    /// Vet a pending edit against chip atomicity and the read-only bibliography.
    ///
    /// - Returns `.reject` when the edit intrudes on the bibliography region
    ///   without covering it.
    /// - Returns `.handled` when the edit partially intersects chip runs (or is
    ///   a backspace right after a chip): the range is expanded to whole chips
    ///   and the replacement performed programmatically.
    /// - Returns `.allow` otherwise.
    func decideEdit(range: NSRange, replacement: String) -> EditDecision {
        // Our own programmatic replacement re-enters the hook — let it through.
        guard !isPerformingCitationEdit else { return .allow }
        guard let textStorage = textContentStorage.textStorage else { return .allow }

        // Read-only bibliography: reject intrusions that don't cover the region.
        if !CitationController.editAllowedAgainstBibliography(range, in: textStorage) {
            return .reject
        }

        let isDeletion = replacement.isEmpty
        let expanded = CitationController.expandToCoverChips(
            range, in: textStorage, isDeletion: isDeletion
        )
        guard expanded != range else { return .allow }

        // The edit touches a chip: perform the expanded replacement ourselves.
        let replacementAttr = NSAttributedString(
            string: replacement,
            attributes: replacement.isEmpty ? nil : typingAttributesForEdit(at: expanded.location)
        )
        performCitationReplacement(
            range: expanded, with: replacementAttr,
            actionName: replacement.isEmpty ? "Delete" : "Replace"
        )
        // Place the caret after the inserted text.
        let caret = expanded.location + replacementAttr.length
        applySelectionToTextView([NSRange(location: caret, length: 0)])
        selectionDidChange(NSRange(location: caret, length: 0))
        return .handled
    }

    /// Plain block-styled attributes for text typed over a chip boundary —
    /// never carries `.writeCitation`.
    private func typingAttributesForEdit(at location: Int) -> [NSAttributedString.Key: Any] {
        guard let textStorage = textContentStorage.textStorage,
              textStorage.length > 0 else {
            return [.writeBlockStyle: activeBlockStyle.rawValue]
        }
        let safe = min(max(0, location), textStorage.length - 1)
        let style = textStorage.blockStyle(at: safe)
        var attrs: [NSAttributedString.Key: Any] = [.writeBlockStyle: style.rawValue]
        if !activeTraits.isEmpty {
            attrs[.writeInlineTraits] = NSNumber(value: activeTraits.rawValue)
        }
        return attrs
    }

    // MARK: - Citation usage & navigation

    /// Map of citekey → ranges of every chip that cites it, for the manager.
    var citationUsage: [String: [NSRange]] {
        _ = markdown
        guard let textStorage = textContentStorage.textStorage else { return [:] }
        var usage: [String: [NSRange]] = [:]
        for run in CitationController.chipRuns(in: textStorage) {
            for ref in run.refs {
                usage[ref.itemID, default: []].append(run.range)
            }
        }
        return usage
    }

    /// Scroll a citation chip into view (reusing the heading scroll machinery)
    /// and place the caret just before it.
    func jumpToCitation(at range: NSRange) {
        scrollTo(range: range)
    }

    // MARK: - View geometry (for the popover)

    /// The on-screen rect (text-view coordinates) of `range`, for anchoring the
    /// locator popover. Computed from the TextKit 2 layout fragment plus the
    /// container origin/insets. Nil if layout isn't available.
    func viewRect(forCharacterRange range: NSRange) -> CGRect? {
        let contentStorage = textContentStorage
        let documentStart = contentStorage.documentRange.location
        guard let start = contentStorage.location(documentStart, offsetBy: range.location),
              let end = contentStorage.location(start, offsetBy: max(range.length, 1)),
              let textRange = NSTextRange(location: start, end: end) else { return nil }

        textLayoutManager.ensureLayout(for: textRange)

        var rect: CGRect?
        textLayoutManager.enumerateTextSegments(
            in: textRange, type: .standard, options: []
        ) { _, segmentFrame, _, _ in
            rect = rect.map { $0.union(segmentFrame) } ?? segmentFrame
            return true
        }
        guard var frame = rect else { return nil }

        #if os(macOS)
        if let textView = nativeTextView {
            let origin = textView.textContainerOrigin
            frame = frame.offsetBy(dx: origin.x, dy: origin.y)
        }
        #else
        if let textView = nativeTextView {
            frame = frame.offsetBy(
                dx: textView.textContainerInset.left,
                dy: textView.textContainerInset.top
            )
        }
        #endif
        return frame
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
