import SwiftUI

@main
struct WriteApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            DocumentEditorView(document: file.$document)
                #if os(macOS)
                .onAppear { configureWindow() }
                #endif
        }
        #if os(macOS)
        .commands { ZoomCommands() }
        #endif
    }

    #if os(macOS)
    private static let configuredKey = UnsafeRawPointer(
        UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
    )

    private func configureWindow() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
                  !(window is NSPanel),
                  objc_getAssociatedObject(window, WriteApp.configuredKey) == nil
            else { return }

            objc_setAssociatedObject(window, WriteApp.configuredKey, true, .OBJC_ASSOCIATION_RETAIN)

            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
        }
    }
    #endif
}

#if os(macOS)
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            _ = try? NSDocumentController.shared.openUntitledDocumentAndDisplay(true)
            for window in NSApplication.shared.windows where window is NSOpenPanel {
                window.close()
            }
        }
    }
}
#endif

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
