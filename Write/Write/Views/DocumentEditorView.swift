import SwiftUI

struct DocumentEditorView: View {
    @Binding var document: MarkdownDocument
    @State private var viewModel: EditorViewModel

    init(document: Binding<MarkdownDocument>) {
        self._document = document
        self._viewModel = State(initialValue: EditorViewModel(text: document.wrappedValue.rawText))
    }

    var body: some View {
        editorView
            .onChange(of: viewModel.text) { _, newValue in
                document.rawText = newValue
            }
            #if os(macOS)
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    Button(action: viewModel.toggleBold) {
                        Label("Bold", systemImage: "bold")
                    }
                    .help("Bold (⌘B)")

                    Button(action: viewModel.toggleItalic) {
                        Label("Italic", systemImage: "italic")
                    }
                    .help("Italic (⌘I)")

                    Button(action: viewModel.toggleUnderline) {
                        Label("Underline", systemImage: "underline")
                    }
                    .help("Underline")

                    Divider()

                    Button(action: viewModel.toggleStrikethrough) {
                        Label("Strikethrough", systemImage: "strikethrough")
                    }
                    .help("Strikethrough")

                    Button(action: viewModel.toggleSuperscript) {
                        Label("Superscript", systemImage: "textformat.superscript")
                    }
                    .help("Superscript")

                    Button(action: viewModel.toggleSubscript) {
                        Label("Subscript", systemImage: "textformat.subscript")
                    }
                    .help("Subscript")

                    Divider()

                    Button(action: viewModel.toggleInlineCode) {
                        Label("Inline Code", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    .help("Inline Code")
                }
            }
            #endif
            .focusedValue(\.editorViewModel, viewModel)
    }

    @ViewBuilder
    private var editorView: some View {
        #if os(macOS)
        MacEditorView(viewModel: viewModel)
        #else
        IOSEditorView(viewModel: viewModel)
        #endif
    }
}
