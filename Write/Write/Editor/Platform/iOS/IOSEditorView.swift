#if os(iOS)
import UIKit
import SwiftUI
import UniformTypeIdentifiers

final class WriteUITextView: UITextView {
    var viewModel: EditorViewModel?

    /// Width of the text column; margins grow beyond this on wide layouts.
    static let columnWidth: CGFloat = 680

    /// ⌘↩ converts the URL/DOI token at the caret into a citation chip.
    override var keyCommands: [UIKeyCommand]? {
        let cite = UIKeyCommand(
            input: "\r", modifierFlags: .command, action: #selector(citeAtCaret(_:))
        )
        cite.wantsPriorityOverSystemBehavior = true
        return [cite]
    }

    @objc private func citeAtCaret(_ sender: UIKeyCommand) {
        viewModel?.citeTokenAtCaret()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Equal padding on all four sides; side margins only grow beyond it
        // to center the column on wide layouts. iPad adds top clearance so
        // text doesn't slide under the floating back/title pill (its
        // navigation bar is hidden and reserves no space).
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let basePadding: CGFloat = isPad ? 28 : 20
        let topPadding: CGFloat = isPad ? 64 : basePadding
        let margin = max(basePadding, (bounds.width - Self.columnWidth) / 2).rounded()
        let insets = UIEdgeInsets(top: topPadding, left: margin, bottom: basePadding, right: margin)
        if textContainerInset != insets {
            textContainerInset = insets
        }
    }

    override func paste(_ sender: Any?) {
        // An image-only clipboard (no text) pastes as an inserted image; the
        // original bytes are preserved. Otherwise fall back to plain text.
        let pasteboard = UIPasteboard.general
        if !pasteboard.hasStrings, let (data, ext) = Self.imagePayload(from: pasteboard) {
            viewModel?.insertImage(data: data, fileExtension: ext)
            return
        }
        guard let plainText = pasteboard.string else {
            super.paste(sender)
            return
        }
        insertText(plainText)
    }

    /// Image bytes + extension from a pasteboard, preferring typed
    /// representations (so the original format/bytes survive) before falling
    /// back to the generic `image` accessor.
    static func imagePayload(from pasteboard: UIPasteboard) -> (Data, String)? {
        guard pasteboard.hasImages else { return nil }
        // Prefer concrete UTType data so the original bytes/extension survive.
        let typeExt: [(String, String)] = [
            (UTType.png.identifier, "png"),
            (UTType.jpeg.identifier, "jpeg"),
            (UTType.heic.identifier, "heic"),
            (UTType.gif.identifier, "gif"),
            (UTType.tiff.identifier, "tiff"),
        ]
        for (type, ext) in typeExt {
            if let data = pasteboard.data(forPasteboardType: type) {
                return (data, ext)
            }
        }
        // Fallback: re-encode the generic image as PNG (lossless).
        if let image = pasteboard.image, let data = image.pngData() {
            return (data, "png")
        }
        return nil
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

        // iPhone only: iPad already shows the system shortcut bar above the
        // keyboard (whose B/I/U route to our toggles) plus the floating
        // formatting bar — stacking ours under those doubles the controls.
        // (UIDevice, not traitCollection: traits aren't resolved until the
        // view joins a window, so they misreport here.)
        if UIDevice.current.userInterfaceIdiom == .phone {
            textView.inputAccessoryView = FormattingAccessoryBar.make(viewModel: viewModel)
        }

        let handle = IOSParagraphHandleController(viewModel: viewModel, textView: textView)
        context.coordinator.handleController = handle

        // A tap that lands on a chip or an image opens its popover; it fails
        // otherwise so normal caret placement and editing are untouched.
        let chipTap = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleChipTap(_:))
        )
        chipTap.delegate = context.coordinator
        chipTap.cancelsTouchesInView = false
        textView.addGestureRecognizer(chipTap)
        context.coordinator.chipTap = chipTap

        context.coordinator.textView = textView
        viewModel.nativeTextView = textView
        viewModel.refreshStyle()

        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        let viewModel: EditorViewModel
        weak var textView: UITextView?
        var handleController: IOSParagraphHandleController?
        weak var chipTap: UITapGestureRecognizer?
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

            // Chip atomicity + read-only bibliography enforcement.
            switch viewModel.decideEdit(range: range, replacement: text) {
            case .allow:
                return true
            case .reject, .handled:
                lastEditInsertedNewline = false
                return false
            }
        }

        // MARK: Chip / image tap

        /// The chip range under a point in the text view, or nil.
        private func chipRange(at point: CGPoint, in textView: UITextView) -> NSRange? {
            guard let textStorage = viewModel.textContentStorage.textStorage,
                  textStorage.length > 0 else { return nil }
            // Closest position to the touch.
            guard let position = textView.closestPosition(to: point) else { return nil }
            let index = textView.offset(from: textView.beginningOfDocument, to: position)
            for candidate in [index, index - 1] where candidate >= 0 && candidate < textStorage.length {
                guard let chip = CitationController.chipRange(at: candidate, in: textStorage) else { continue }
                if let rect = viewModel.viewRect(forCharacterRange: chip), rect.contains(point) {
                    return chip
                }
            }
            return nil
        }

        /// The image attachment range under a point in the text view, or nil.
        private func imageRange(at point: CGPoint, in textView: UITextView) -> NSRange? {
            guard let textStorage = viewModel.textContentStorage.textStorage,
                  textStorage.length > 0 else { return nil }
            guard let position = textView.closestPosition(to: point) else { return nil }
            let index = textView.offset(from: textView.beginningOfDocument, to: position)
            for candidate in [index, index - 1] where candidate >= 0 && candidate < textStorage.length {
                guard textStorage.attribute(.writeImage, at: candidate, effectiveRange: nil) is String
                else { continue }
                var effective = NSRange(location: 0, length: 0)
                textStorage.attribute(
                    .writeImage, at: candidate, longestEffectiveRange: &effective,
                    in: NSRange(location: 0, length: textStorage.length)
                )
                if let rect = viewModel.viewRect(forCharacterRange: effective), rect.contains(point) {
                    return effective
                }
            }
            return nil
        }

        @objc func handleChipTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let textView else { return }
            let point = gesture.location(in: textView)
            // Images take precedence over chips (mirrors macOS mouseDown), though
            // the two never overlap on the same character.
            if let image = imageRange(at: point, in: textView) {
                viewModel.pendingImagePopoverRange = image
                return
            }
            if let chip = chipRange(at: point, in: textView) {
                viewModel.pendingPopoverChipRange = chip
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            // Only accept the touch if it lands on a chip or an image — otherwise
            // let the text view handle it normally (this recognizer simply fails).
            guard gestureRecognizer === chipTap, let textView else { return true }
            let point = touch.location(in: textView)
            return imageRange(at: point, in: textView) != nil
                || chipRange(at: point, in: textView) != nil
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
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
