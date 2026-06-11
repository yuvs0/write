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
            styleMenu

            Divider().frame(height: 16)

            button("bold", "Bold (⌘B)", .bold, viewModel.toggleBold)
            button("italic", "Italic (⌘I)", .italic, viewModel.toggleItalic)
            button("underline", "Underline (⌘U)", .underline, viewModel.toggleUnderline)

            Divider().frame(height: 16)

            button("strikethrough", "Strikethrough", .strikethrough, viewModel.toggleStrikethrough)
            button("textformat.superscript", "Superscript", .superscript, viewModel.toggleSuperscript)
            button("textformat.subscript", "Subscript", .subscriptText, viewModel.toggleSubscript)

            Divider().frame(height: 16)

            button(
                "chevron.left.forwardslash.chevron.right", "Inline Code (⌘E)",
                .code, viewModel.toggleInlineCode
            )
        }
        .padding(.horizontal, 4)
    }

    private var styleMenu: some View {
        Menu {
            ForEach(BlockStyle.menuStyles, id: \.self) { style in
                Toggle(
                    style.displayName,
                    isOn: Binding(
                        get: { viewModel.activeBlockStyle == style },
                        set: { _ in viewModel.setBlockStyle(style) }
                    )
                )
            }
        } label: {
            Text(viewModel.activeBlockStyle.displayName)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Paragraph style")
    }

    private func button(
        _ icon: String,
        _ tooltip: String,
        _ trait: InlineTraits,
        _ action: @escaping () -> Void
    ) -> some View {
        let isActive = viewModel.activeTraits.contains(trait)
        return Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                .frame(width: 28, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}
#endif
