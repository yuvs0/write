import SwiftUI

@main
struct WriteApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            DocumentEditorView(document: file.$document)
                #if os(macOS)
                .onAppear { configureWindow() }
                #endif
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .commands { ZoomCommands() }
        #endif
    }

    #if os(macOS)
    private func configureWindow() {
        DispatchQueue.main.async {
            for window in NSApplication.shared.windows {
                window.isOpaque = false
                window.backgroundColor = .clear
                window.styleMask.insert(.fullSizeContentView)
                window.titlebarAppearsTransparent = true
                window.isMovableByWindowBackground = true
                if let contentView = window.contentView {
                    contentView.wantsLayer = true
                    contentView.layer?.cornerRadius = 18
                    contentView.layer?.masksToBounds = true
                }
            }
        }
    }
    #endif
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
