import SwiftUI

/// Popover content for an image attachment: edit the caption, toggle the
/// "numbered figure" flag, or remove the image. Edits apply through the view
/// model (rewriting the `.writeImage` JSON, rebuilding the attachment so the
/// caption re-renders, restyling, serializing) — undo-aware.
struct ImagePopover: View {
    @Bindable var viewModel: EditorViewModel
    /// The image attachment's character range. Captured at presentation.
    let imageRange: NSRange
    /// Called to dismiss the popover.
    var onDismiss: () -> Void

    @State private var caption: String
    @State private var isFigure: Bool

    init(viewModel: EditorViewModel, imageRange: NSRange, onDismiss: @escaping () -> Void) {
        self.viewModel = viewModel
        self.imageRange = imageRange
        self.onDismiss = onDismiss
        let ref = viewModel.imageRef(at: imageRange)
        _caption = State(initialValue: ref?.caption ?? "")
        _isFigure = State(initialValue: ref?.isFigure ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Image")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Caption")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("Describe the image…", text: $caption, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        applyEdits()
                        onDismiss()
                    }
                    #if os(iOS)
                    .autocorrectionDisabled(false)
                    #endif

                Toggle("Numbered figure", isOn: $isFigure)
            }

            Divider()

            HStack {
                Button(role: .destructive) {
                    viewModel.removeImage(at: imageRange)
                    onDismiss()
                } label: {
                    Label("Remove Image", systemImage: "trash")
                }
                .buttonStyle(.borderless)

                Spacer()

                Button("Done") {
                    applyEdits()
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    private func applyEdits() {
        viewModel.updateImage(
            at: imageRange,
            caption: caption.trimmingCharacters(in: .whitespacesAndNewlines),
            isFigure: isFigure
        )
    }
}
