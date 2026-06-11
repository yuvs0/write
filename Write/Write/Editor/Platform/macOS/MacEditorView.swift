#if os(macOS)
import AppKit
import SwiftUI

final class WriteTextView: NSTextView {
    var onPaste: (() -> Void)?
    var onMouseMoved: ((NSPoint?) -> Void)?

    /// Width of the text column; margins grow beyond this to keep prose
    /// comfortable to read and leave a gutter for the paragraph handle.
    static let columnWidth: CGFloat = 680
    static let minimumMargin: CGFloat = 64

    override func paste(_ sender: Any?) {
        pasteAsPlainText(sender)
        onPaste?()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let margin = max(Self.minimumMargin, (newSize.width - Self.columnWidth) / 2)
        let inset = NSSize(width: margin.rounded(), height: 28)
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
        textView.textContainerInset = NSSize(width: WriteTextView.minimumMargin, height: 28)
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
            return true
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
            viewModel.selectionDidChange(textView.selectedRange())
        }
    }
}
#endif
