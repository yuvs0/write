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
                ToolbarItem(placement: .primaryAction) {
                    CollapsibleToolbar(viewModel: viewModel)
                }
            }
            .background {
                VisualEffectBackground()
                    .ignoresSafeArea()
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
