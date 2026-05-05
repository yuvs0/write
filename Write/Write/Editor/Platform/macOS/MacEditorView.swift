#if os(macOS)
import AppKit
import SwiftUI

final class WriteTextView: NSTextView {
    var onPaste: (() -> Void)?

    override func paste(_ sender: Any?) {
        pasteAsPlainText(sender)
        onPaste?()
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
        textView.isRichText = false
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 20, height: 20)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.delegate = context.coordinator

        scrollView.documentView = textView

        textView.onPaste = { [weak viewModel] in
            viewModel?.applyHighlighting()
        }

        context.coordinator.textView = textView
        viewModel.nativeTextView = textView
        viewModel.applyHighlighting()

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let viewModel: EditorViewModel
        weak var textView: NSTextView?
        private var isUpdating = false

        init(viewModel: EditorViewModel) {
            self.viewModel = viewModel
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView else { return }
            isUpdating = true
            let editedRange = textView.selectedRange()
            viewModel.handleTextChange(textView.string, editedRange: editedRange)
            isUpdating = false
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            viewModel.savedSelectedRange = textView.selectedRange()
        }
    }
}
#endif
