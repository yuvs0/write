#if os(iOS)
import SwiftUI
import UIKit

/// Formatting bar shown above the on-screen keyboard. This is the primary
/// formatting surface on iPhone, where there is no menu bar or hover handle.
enum FormattingAccessoryBar {
    static func make(viewModel: EditorViewModel) -> UIView {
        FormattingBarInputView(viewModel: viewModel)
    }
}

/// Hosts the SwiftUI bar inside a keyboard-styled input view, keeping the
/// hosting controller alive for the bar's lifetime.
private final class FormattingBarInputView: UIInputView {
    private let host: UIHostingController<FormattingBarContent>

    init(viewModel: EditorViewModel) {
        host = UIHostingController(rootView: FormattingBarContent(viewModel: viewModel))
        super.init(
            frame: CGRect(x: 0, y: 0, width: 0, height: 48),
            inputViewStyle: .keyboard
        )
        allowsSelfSizing = true
        host.view.backgroundColor = .clear
        host.sizingOptions = .intrinsicContentSize
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: topAnchor),
            host.view.bottomAnchor.constraint(equalTo: bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct FormattingBarContent: View {
    @Bindable var viewModel: EditorViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                styleMenu

                Divider().frame(height: 20)

                traitButton("bold", "Bold", .bold) { viewModel.toggleBold() }
                traitButton("italic", "Italic", .italic) { viewModel.toggleItalic() }
                traitButton("underline", "Underline", .underline) { viewModel.toggleUnderline() }
                traitButton("strikethrough", "Strikethrough", .strikethrough) {
                    viewModel.toggleStrikethrough()
                }
                traitButton(
                    "chevron.left.forwardslash.chevron.right", "Code", .code
                ) { viewModel.toggleInlineCode() }

                Divider().frame(height: 20)

                imageButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(height: 48)
    }

    private var imageButton: some View {
        Button {
            viewModel.requestsPhotoPicker = true
        } label: {
            Image(systemName: "photo")
                .font(.system(size: 15, weight: .medium))
                .frame(width: 38, height: 34)
                .foregroundStyle(Color.primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Insert Image")
    }

    private var styleMenu: some View {
        Menu {
            ForEach(Array(BlockStyle.menuSections.enumerated()), id: \.offset) { sectionIndex, section in
                Section {
                    ForEach(section, id: \.self) { style in
                        styleButton(style)
                    }
                    if sectionIndex == 0 {
                        Menu("More Headings") {
                            ForEach(BlockStyle.moreHeadings, id: \.self) { style in
                                styleButton(style)
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(viewModel.activeBlockStyle.displayName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func styleButton(_ style: BlockStyle) -> some View {
        Button {
            viewModel.setBlockStyle(style)
        } label: {
            if style == viewModel.activeBlockStyle {
                Label(style.displayName, systemImage: "checkmark")
            } else {
                Text(style.displayName)
            }
        }
    }

    private func traitButton(
        _ icon: String,
        _ label: String,
        _ trait: InlineTraits,
        action: @escaping () -> Void
    ) -> some View {
        let isActive = viewModel.activeTraits.contains(trait)
        return Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 38, height: 34)
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
#endif
