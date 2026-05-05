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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    Divider()
                    MacFormattingBar(viewModel: viewModel)
                }
                .background {
                    VisualEffectBackground(material: .sidebar, blendingMode: .withinWindow)
                        .ignoresSafeArea()
                }
            }
            .background {
                VisualEffectBackground(material: .sidebar, blendingMode: .behindWindow, cornerRadius: 16)
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
