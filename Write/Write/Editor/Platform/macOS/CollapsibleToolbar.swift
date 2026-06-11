#if os(macOS)
import SwiftUI

/// Floating formatting bar, layered over the editor (not inside the window
/// toolbar — toolbar items get their own Liquid Glass on macOS 26, which
/// would double-wrap ours and fight the expansion animation).
///
/// The collapsed glyph and expanded bar share a `glassEffectID` inside one
/// `GlassEffectContainer`, so the system performs the Liquid Glass morph
/// between the two shapes. Hover tracking lives on the container, which is
/// never replaced, so the hover region stays stable while the branches swap.
struct CollapsibleToolbar: View {
    @Bindable var viewModel: EditorViewModel
    @State private var isExpanded = false
    @State private var collapseTask: Task<Void, Never>?
    @Namespace private var glassNamespace

    /// How long the bar stays expanded after the pointer leaves.
    private static let collapseGracePeriod: Duration = .seconds(10)

    var body: some View {
        GlassEffectContainer {
            if isExpanded {
                formattingButtons
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: .capsule)
                    .glassEffectID("formatting", in: glassNamespace)
            } else {
                Image(systemName: "textformat")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 34, height: 34)
                    .contentShape(.circle)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .glassEffectID("formatting", in: glassNamespace)
            }
        }
        .onHover { hovering in
            collapseTask?.cancel()
            collapseTask = nil
            if hovering {
                withAnimation(.smooth(duration: 0.3)) {
                    isExpanded = true
                }
            } else {
                // Linger so the bar doesn't vanish the moment the pointer
                // slips out; hovering back in cancels the collapse.
                collapseTask = Task { @MainActor in
                    try? await Task.sleep(for: Self.collapseGracePeriod)
                    guard !Task.isCancelled else { return }
                    withAnimation(.smooth(duration: 0.3)) {
                        isExpanded = false
                    }
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
        .fixedSize()
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
