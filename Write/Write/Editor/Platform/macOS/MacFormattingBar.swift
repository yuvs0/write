#if os(macOS)
import SwiftUI

struct MacFormattingBar: View {
    @Bindable var viewModel: EditorViewModel

    var body: some View {
        HStack(spacing: 0) {
            group([
                BarButton(icon: "bold", tooltip: "Bold (⌘B)", action: viewModel.toggleBold),
                BarButton(icon: "italic", tooltip: "Italic (⌘I)", action: viewModel.toggleItalic),
                BarButton(icon: "underline", tooltip: "Underline", action: viewModel.toggleUnderline),
            ])

            separator

            group([
                BarButton(icon: "strikethrough", tooltip: "Strikethrough", action: viewModel.toggleStrikethrough),
                BarButton(icon: "textformat.superscript", tooltip: "Superscript", action: viewModel.toggleSuperscript),
                BarButton(icon: "textformat.subscript", tooltip: "Subscript", action: viewModel.toggleSubscript),
            ])

            separator

            group([
                BarButton(icon: "chevron.left.forwardslash.chevron.right", tooltip: "Inline Code", action: viewModel.toggleInlineCode),
            ])
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .glassEffect(.regular, in: Capsule())
    }

    private var separator: some View {
        Divider()
            .frame(height: 18)
            .padding(.horizontal, 4)
    }

    private func group(_ buttons: [BarButton]) -> some View {
        HStack(spacing: 0) {
            ForEach(buttons) { $0 }
        }
    }
}

private struct BarButton: View, Identifiable {
    let id = UUID()
    let icon: String
    let tooltip: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .regular))
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}
#endif
