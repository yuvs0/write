#if os(iOS)
import UIKit
import SwiftUI

final class WriteUITextView: UITextView {
    var viewModel: EditorViewModel?

    /// Width of the text column; margins grow beyond this on wide layouts.
    static let columnWidth: CGFloat = 680

    override func layoutSubviews() {
        super.layoutSubviews()
        // Equal padding on all four sides; side margins only grow beyond it
        // to center the column on wide layouts.
        let basePadding: CGFloat = traitCollection.userInterfaceIdiom == .pad ? 28 : 20
        let margin = max(basePadding, (bounds.width - Self.columnWidth) / 2).rounded()
        let insets = UIEdgeInsets(top: basePadding, left: margin, bottom: basePadding, right: margin)
        if textContainerInset != insets {
            textContainerInset = insets
        }
    }

    override func paste(_ sender: Any?) {
        guard let plainText = UIPasteboard.general.string else {
            super.paste(sender)
            return
        }
        insertText(plainText)
    }

    override func toggleBoldface(_ sender: Any?) {
        viewModel?.toggleBold()
    }

    override func toggleItalics(_ sender: Any?) {
        viewModel?.toggleItalic()
    }

    override func toggleUnderline(_ sender: Any?) {
        viewModel?.toggleUnderline()
    }
}

struct IOSEditorView: UIViewRepresentable {
    @Bindable var viewModel: EditorViewModel

    func makeUIView(context: Context) -> UITextView {
        let textView = WriteUITextView(frame: .zero, textContainer: viewModel.textContainer)
        textView.viewModel = viewModel
        textView.isEditable = true
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 24, left: 20, bottom: 24, right: 20)
        textView.contentInsetAdjustmentBehavior = .automatic
        textView.keyboardDismissMode = .interactive
        textView.alwaysBounceVertical = true
        textView.autocorrectionType = .default
        textView.autocapitalizationType = .sentences
        textView.smartQuotesType = .yes
        textView.smartDashesType = .yes
        textView.allowsEditingTextAttributes = false
        textView.delegate = context.coordinator

        textView.inputAccessoryView = FormattingAccessoryBar.make(viewModel: viewModel)

        let handle = IOSParagraphHandleController(viewModel: viewModel, textView: textView)
        context.coordinator.handleController = handle

        context.coordinator.textView = textView
        viewModel.nativeTextView = textView
        viewModel.refreshStyle()

        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        let viewModel: EditorViewModel
        weak var textView: UITextView?
        var handleController: IOSParagraphHandleController?
        private var isUpdating = false
        private var lastEditInsertedNewline = false

        init(viewModel: EditorViewModel) {
            self.viewModel = viewModel
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            if text == "\n", viewModel.handleReturnKey() {
                return false
            }
            lastEditInsertedNewline = text.contains("\n")
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdating else { return }
            isUpdating = true
            viewModel.handleTextChange(
                editedRange: textView.selectedRange,
                insertedNewline: lastEditInsertedNewline
            )
            lastEditInsertedNewline = false
            isUpdating = false
            handleController?.hide()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            viewModel.selectionDidChange(textView.selectedRange)
        }
    }
}
#endif
