#if os(macOS)
import SwiftUI

struct CollapsibleToolbar: View {
    @Bindable var viewModel: EditorViewModel
    @State private var isExpanded = false
    @State private var buttonsWidth: CGFloat = 0

    var body: some View {
        HStack(spacing: 0) {
            formattingButtons
                .fixedSize()
                .frame(width: isExpanded ? buttonsWidth : 0, alignment: .leading)
                .clipped()
                .opacity(isExpanded ? 1 : 0)

            Image(systemName: "textformat")
                .font(.system(size: 12, weight: .medium))
                .frame(width: isExpanded ? 0 : 28, height: 28)
                .opacity(isExpanded ? 0 : 1)
                .clipped()
        }
        .padding(.horizontal, isExpanded ? 8 : 0)
        .padding(.vertical, 4)
        .glassEffect(.regular, in: .capsule)
        .contentShape(Capsule())
        .onHover { hovering in
            withAnimation(.spring(duration: 0.35, bounce: 0.12)) {
                isExpanded = hovering
            }
        }
        .background(
            formattingButtons
                .fixedSize()
                .hidden()
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { width in
                    buttonsWidth = width
                }
        )
    }

    private var formattingButtons: some View {
        HStack(spacing: 4) {
            button("bold", "Bold (⌘B)", viewModel.toggleBold)
            button("italic", "Italic (⌘I)", viewModel.toggleItalic)
            button("underline", "Underline", viewModel.toggleUnderline)

            Divider().frame(height: 16)

            button("strikethrough", "Strikethrough", viewModel.toggleStrikethrough)
            button("textformat.superscript", "Superscript", viewModel.toggleSuperscript)
            button("textformat.subscript", "Subscript", viewModel.toggleSubscript)

            Divider().frame(height: 16)

            button("chevron.left.forwardslash.chevron.right", "Inline Code", viewModel.toggleInlineCode)
        }
        .padding(.horizontal, 4)
    }

    private func button(_ icon: String, _ tooltip: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .regular))
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}
#endif
