#if os(macOS)
import SwiftUI

struct CollapsibleToolbar: View {
    @Bindable var viewModel: EditorViewModel
    @Namespace private var toolbarNamespace
    @State private var isExpanded = false

    var body: some View {
        GlassEffectContainer {
            if isExpanded {
                expandedContent
            } else {
                collapsedContent
            }
        }
        .onHover { hovering in
            withAnimation(.bouncy) {
                isExpanded = hovering
            }
        }
    }

    private var collapsedContent: some View {
        Text("Aa")
            .font(.system(size: 14, weight: .medium, design: .serif))
            .frame(width: 36, height: 36)
            .glassEffect(.regular, in: .circle)
            .glassEffectID("toolbar", in: toolbarNamespace)
    }

    private var expandedContent: some View {
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
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .glassEffect(.regular, in: .capsule)
        .glassEffectID("toolbar", in: toolbarNamespace)
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
