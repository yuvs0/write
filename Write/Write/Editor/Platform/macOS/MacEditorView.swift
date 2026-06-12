#if os(macOS)
import AppKit
import SwiftUI

final class WriteTextView: NSTextView {
    var onPaste: (() -> Void)?
    var onMouseMoved: ((NSPoint?) -> Void)?
    /// Invoked when ⌘↩ is pressed: convert the token at the caret to a chip.
    var onCiteShortcut: (() -> Void)?
    /// Asked whether a click landed on a chip run; if it returns a range, the
    /// view opens that chip's popover and suppresses caret placement.
    var chipRangeAtPoint: ((NSPoint) -> NSRange?)?
    /// Invoked with a chip range to open its locator popover.
    var onChipClicked: ((NSRange) -> Void)?
    /// Asked whether a click landed on an image attachment; if it returns a
    /// range, the view opens that image's popover and suppresses caret placement.
    var imageRangeAtPoint: ((NSPoint) -> NSRange?)?
    /// Invoked with an image range to open its caption popover.
    var onImageClicked: ((NSRange) -> Void)?
    /// Insert image bytes (from a paste or a drop) at a character index (nil =
    /// at the caret). Returns false when the data couldn't be used.
    var onInsertImage: ((Data, String, Int?) -> Void)?

    /// Width of the text column; side margins grow beyond the base padding
    /// only to center the column. The hover handle floats inside the margin.
    static let columnWidth: CGFloat = 680
    static let basePadding: CGFloat = 28

    override func paste(_ sender: Any?) {
        // If the clipboard carries image data and no plain text, paste it as an
        // image. Otherwise fall back to the plain-text paste path.
        let pasteboard = NSPasteboard.general
        let hasText = pasteboard.string(forType: .string)?.isEmpty == false
        if !hasText, let (data, ext) = Self.imagePayload(from: pasteboard) {
            onInsertImage?(data, ext, nil)
            return
        }
        pasteAsPlainText(sender)
        onPaste?()
    }

    /// Image bytes + extension from a pasteboard, preferring file URLs (so the
    /// original format/bytes survive) then raw image data types.
    static func imagePayload(from pasteboard: NSPasteboard) -> (Data, String)? {
        // File URLs (e.g. copied from Finder).
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingContentsConformToTypes: ["public.image"]]
        ) as? [URL], let url = urls.first, let data = try? Data(contentsOf: url) {
            return (data, url.pathExtension)
        }
        // Raw image data types.
        let typeExt: [(NSPasteboard.PasteboardType, String)] = [
            (.png, "png"),
            (.tiff, "tiff"),
            (NSPasteboard.PasteboardType("public.jpeg"), "jpeg"),
            (NSPasteboard.PasteboardType("com.compuserve.gif"), "gif"),
        ]
        for (type, ext) in typeExt {
            if let data = pasteboard.data(forType: type) {
                return (data, ext)
            }
        }
        return nil
    }

    override func keyDown(with event: NSEvent) {
        // ⌘↩ converts the URL/DOI token at the caret into a citation chip.
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if isReturn, event.modifierFlags.contains(.command), let onCiteShortcut {
            onCiteShortcut()
            return
        }
        super.keyDown(with: event)
    }

    /// ⌘-drag adds to the selection instead of replacing it, so formatting
    /// can apply to several stretches of text at once. (TextKit 2 text
    /// views no longer do this themselves.)
    override func mouseDown(with event: NSEvent) {
        // A plain click on a chip or image opens its popover, not a caret.
        if !event.modifierFlags.contains(.command),
           !event.modifierFlags.contains(.shift) {
            let point = convert(event.locationInWindow, from: nil)
            if let imageRange = imageRangeAtPoint?(point) {
                onImageClicked?(imageRange)
                return
            }
            if let chipRange = chipRangeAtPoint?(point) {
                onChipClicked?(chipRange)
                return
            }
        }

        let isAdditive = event.modifierFlags.contains(.command)
            && !event.modifierFlags.contains(.shift)
        let previousRanges = isAdditive
            ? selectedRanges.map(\.rangeValue).filter { $0.length > 0 }
            : []

        super.mouseDown(with: event)

        guard isAdditive, !previousRanges.isEmpty else { return }
        var ranges = previousRanges + selectedRanges.map(\.rangeValue).filter { $0.length > 0 }
        guard ranges.count > 1 else { return }

        ranges.sort { $0.location < $1.location }
        var merged: [NSRange] = []
        for range in ranges {
            if let last = merged.last, NSMaxRange(last) >= range.location {
                merged[merged.count - 1] = NSUnionRange(last, range)
            } else {
                merged.append(range)
            }
        }
        setSelectedRanges(merged.map { NSValue(range: $0) }, affinity: .downstream, stillSelecting: false)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let margin = max(Self.basePadding, (newSize.width - Self.columnWidth) / 2)
        let inset = NSSize(width: margin.rounded(), height: Self.basePadding)
        if textContainerInset != inset {
            textContainerInset = inset
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        onMouseMoved?(convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onMouseMoved?(nil)
    }

    // MARK: - Drag & drop (image files / image data)

    /// Register for image-bearing drags. Called from the representable's setup.
    func registerForImageDrags() {
        registerForDraggedTypes([
            .fileURL, .png, .tiff,
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("com.compuserve.gif"),
        ])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.imagePayload(from: sender.draggingPasteboard) != nil ? .copy : super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.imagePayload(from: sender.draggingPasteboard) != nil ? .copy : super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let (data, ext) = Self.imagePayload(from: sender.draggingPasteboard) else {
            return super.performDragOperation(sender)
        }
        // Drop at the character index nearest the drop point.
        let point = convert(sender.draggingLocation, from: nil)
        let index = characterIndexForInsertion(at: point)
        onInsertImage?(data, ext, index)
        return true
    }
}

struct MacEditorView: NSViewRepresentable {
    @Bindable var viewModel: EditorViewModel

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false

        let textView = WriteTextView(frame: .zero, textContainer: viewModel.textContainer)
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = true
        textView.usesFontPanel = false
        textView.importsGraphics = false
        textView.usesFindBar = true
        // The editor holds prose, not markdown syntax, so smart typography
        // is safe and welcome.
        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.isAutomaticDashSubstitutionEnabled = true
        textView.isAutomaticTextReplacementEnabled = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(
            width: WriteTextView.basePadding, height: WriteTextView.basePadding
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.delegate = context.coordinator

        scrollView.documentView = textView

        textView.onPaste = { [weak viewModel, weak textView] in
            guard let viewModel, let textView else { return }
            viewModel.handleTextChange(editedRange: textView.selectedRange())
        }

        textView.onCiteShortcut = { [weak viewModel] in
            viewModel?.citeTokenAtCaret()
        }

        textView.chipRangeAtPoint = { [weak viewModel, weak textView] point in
            guard let viewModel, let textView else { return nil }
            return Self.chipRange(at: point, in: textView, viewModel: viewModel)
        }

        textView.onChipClicked = { [weak viewModel] chipRange in
            viewModel?.pendingPopoverChipRange = chipRange
        }

        textView.imageRangeAtPoint = { [weak viewModel, weak textView] point in
            guard let viewModel, let textView else { return nil }
            return Self.imageRange(at: point, in: textView, viewModel: viewModel)
        }

        textView.onImageClicked = { [weak viewModel] imageRange in
            viewModel?.pendingImagePopoverRange = imageRange
        }

        textView.onInsertImage = { [weak viewModel] data, ext, index in
            viewModel?.insertImage(data: data, fileExtension: ext, at: index)
        }

        textView.registerForImageDrags()

        let handle = ParagraphHandleController(viewModel: viewModel, textView: textView)
        textView.onMouseMoved = { [weak handle] point in
            handle?.mouseMoved(to: point)
        }
        context.coordinator.handleController = handle

        context.coordinator.textView = textView
        viewModel.nativeTextView = textView
        viewModel.refreshStyle()

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {}

    /// Map a point in the text view to the chip run under it, if any.
    ///
    /// `characterIndexForInsertion(at:)` returns the insertion index nearest the
    /// point; to require the click land *on* a chip (not merely at its edge), we
    /// also verify the click's vertical position falls within a chip segment's
    /// frame via the layout manager.
    private static func chipRange(
        at point: NSPoint, in textView: NSTextView, viewModel: EditorViewModel
    ) -> NSRange? {
        guard let textStorage = viewModel.textContentStorage.textStorage,
              textStorage.length > 0 else { return nil }

        let index = textView.characterIndexForInsertion(at: point)
        // characterIndexForInsertion clamps to length; probe both the index and
        // the character before it (clicking the right half of a chip rounds up).
        let candidates = [index, index - 1].filter { $0 >= 0 && $0 < textStorage.length }
        for candidate in candidates {
            guard let chip = CitationController.chipRange(at: candidate, in: textStorage) else { continue }
            // Confirm the point is within the chip's laid-out rect.
            if let rect = viewModel.viewRect(forCharacterRange: chip), rect.contains(point) {
                return chip
            }
        }
        return nil
    }

    /// Map a point to an image attachment run under it, if any.
    private static func imageRange(
        at point: NSPoint, in textView: NSTextView, viewModel: EditorViewModel
    ) -> NSRange? {
        guard let textStorage = viewModel.textContentStorage.textStorage,
              textStorage.length > 0 else { return nil }
        let index = textView.characterIndexForInsertion(at: point)
        let candidates = [index, index - 1].filter { $0 >= 0 && $0 < textStorage.length }
        for candidate in candidates {
            guard textStorage.attribute(.writeImage, at: candidate, effectiveRange: nil) is String
            else { continue }
            var effective = NSRange(location: 0, length: 0)
            textStorage.attribute(.writeImage, at: candidate, longestEffectiveRange: &effective,
                                  in: NSRange(location: 0, length: textStorage.length))
            if let rect = viewModel.viewRect(forCharacterRange: effective), rect.contains(point) {
                return effective
            }
        }
        return nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let viewModel: EditorViewModel
        weak var textView: NSTextView?
        var handleController: ParagraphHandleController?
        private var isUpdating = false
        private var lastEditInsertedNewline = false

        init(viewModel: EditorViewModel) {
            self.viewModel = viewModel
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            lastEditInsertedNewline = replacementString?.contains("\n") ?? false

            // Attribute-only changes (nil replacement) bypass interception.
            guard let replacementString else { return true }

            // Chip atomicity + read-only bibliography enforcement.
            switch viewModel.decideEdit(range: affectedCharRange, replacement: replacementString) {
            case .allow:
                return true
            case .reject:
                lastEditInsertedNewline = false
                return false
            case .handled:
                lastEditInsertedNewline = false
                return false
            }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                return viewModel.handleReturnKey()
            }
            return false
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView else { return }
            isUpdating = true
            viewModel.handleTextChange(
                editedRange: textView.selectedRange(),
                insertedNewline: lastEditInsertedNewline
            )
            lastEditInsertedNewline = false
            isUpdating = false
            handleController?.hide()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            // ⌘-click selection can be discontiguous; report every range.
            viewModel.selectionDidChange(ranges: textView.selectedRanges.map(\.rangeValue))
        }
    }
}
#endif
