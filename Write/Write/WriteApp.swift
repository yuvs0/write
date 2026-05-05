import SwiftUI

@main
struct WriteApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            DocumentEditorView(document: file.$document)
        }
        #if os(macOS)
        .commands { ZoomCommands() }
        #endif
    }

}

#if os(macOS)
struct ZoomCommands: Commands {
    @FocusedValue(\.editorViewModel) var viewModel

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Zoom In") { viewModel?.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
            Button("Zoom Out") { viewModel?.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
            Button("Actual Size") { viewModel?.resetZoom() }
                .keyboardShortcut("0", modifiers: .command)
        }
    }
}
#endif
