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
            #if os(macOS)
            .background {
                VisualEffectBackground()
                    .ignoresSafeArea()
            }
            #endif
            .onChange(of: viewModel.text) { _, newValue in
                document.rawText = newValue
            }
            #if os(macOS)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    CollapsibleToolbar(viewModel: viewModel)
                }
            }
            #endif
            .focusedValue(\.editorViewModel, viewModel)
    }

    @ViewBuilder
    private var editorView: some View {
        #if os(macOS)
        MacEditorView(viewModel: viewModel)
            .ignoresSafeArea()
        #else
        IOSEditorView(viewModel: viewModel)
            .ignoresSafeArea()
        #endif
    }
}
