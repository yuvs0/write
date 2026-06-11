import SwiftUI

struct OutlineItem: Identifiable {
    let id: Int
    let level: Int
    let title: String
    /// Opening words of the section, shown as a tooltip.
    let preview: String
    let paragraphRange: NSRange
}

/// Document outline sidebar (macOS and iPadOS). Click a heading to jump to
/// it; hover shows the section's first few words.
struct NavigatorView: View {
    @Bindable var viewModel: EditorViewModel

    var body: some View {
        let outline = viewModel.outline
        Group {
            if outline.isEmpty {
                ContentUnavailableView(
                    "No Headings",
                    systemImage: "list.bullet.indent",
                    description: Text("Headings you add will appear here for quick navigation.")
                )
            } else {
                List(outline) { item in
                    Button {
                        viewModel.scrollToHeading(at: item.paragraphRange)
                    } label: {
                        Text(item.title)
                            .font(font(for: item.level))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.leading, CGFloat(item.level - 1) * 14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(item.preview)
                }
                .listStyle(.sidebar)
            }
        }
        .navigationTitle("Outline")
    }

    private func font(for level: Int) -> Font {
        switch level {
        case 1: return .callout.weight(.semibold)
        case 2: return .callout.weight(.medium)
        default: return .callout
        }
    }
}
