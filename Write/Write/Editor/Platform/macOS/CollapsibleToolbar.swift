#if os(macOS)
import SwiftUI

/// Hover-expanding formatting bar. The collapsed glyph and the expanded bar
/// share a glass effect ID inside one container, so the system performs the
/// Liquid Glass morph between the two shapes.
struct CollapsibleToolbar: View {
    @Bindable var viewModel: EditorViewModel
    @State private var isExpanded = false
    @Namespace private var glassNamespace

    var body: some View {
        GlassEffectContainer {
            Group {
                if isExpanded {
                    formattingButtons
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .glassEffectID("formatting", in: glassNamespace)
                } else {
                    Image(systemName: "textformat")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(.circle)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .glassEffectID("formatting", in: glassNamespace)
                }
            }
            .onHover { hovering in
                withAnimation(.smooth(duration: 0.35)) {
                    isExpanded = hovering
                }
            }
        }
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
