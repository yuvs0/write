#if os(iOS)
import UIKit
import SwiftUI

struct IOSEditorView: UIViewRepresentable {
    @Bindable var viewModel: EditorViewModel

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView(frame: .zero, textContainer: viewModel.textContainer)
        textView.isEditable = true
        textView.isSelectable = true
        textView.backgroundColor = .systemBackground
        textView.textContainerInset = UIEdgeInsets(top: 24, left: 16, bottom: 24, right: 16)
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.autocorrectionType = .default
        textView.autocapitalizationType = .sentences
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.delegate = context.coordinator

        context.coordinator.textView = textView
        viewModel.applyHighlighting()

        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        let viewModel: EditorViewModel
        weak var textView: UITextView?
        private var isUpdating = false

        init(viewModel: EditorViewModel) {
            self.viewModel = viewModel
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdating else { return }
            isUpdating = true

            let newText = textView.text ?? ""
            viewModel.text = newText

            if let textStorage = viewModel.textContentStorage.textStorage {
                let editedRange = textView.selectedRange
                let paragraphRange = (newText as NSString).paragraphRange(for: editedRange)
                viewModel.highlighter.highlightRange(paragraphRange, in: textStorage)
            }

            isUpdating = false
        }
    }
}
#endif
