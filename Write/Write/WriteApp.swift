import SwiftUI

@main
struct WriteApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            DocumentEditorView(document: file.$document, fileURL: file.fileURL)
        }
        .commands {
            FormatCommands()
            ExportCommands()
            ZoomCommands()
        }

        #if os(macOS)
        Settings {
            StyleSettingsView()
                .frame(minWidth: 540, minHeight: 480)
        }
        #endif
    }
}

/// Inline and block formatting, mirrored in the menu bar on macOS and iPadOS
/// so every action has a discoverable home and a keyboard shortcut.
struct FormatCommands: Commands {
    @FocusedValue(\.editorViewModel) var viewModel

    var body: some Commands {
        CommandMenu("Format") {
            Button("Bold") { viewModel?.toggleBold() }
                .keyboardShortcut("b", modifiers: .command)
            Button("Italic") { viewModel?.toggleItalic() }
                .keyboardShortcut("i", modifiers: .command)
            Button("Underline") { viewModel?.toggleUnderline() }
                .keyboardShortcut("u", modifiers: .command)
            Button("Strikethrough") { viewModel?.toggleStrikethrough() }
                .keyboardShortcut("x", modifiers: [.command, .shift])
            Button("Inline Code") { viewModel?.toggleInlineCode() }
                .keyboardShortcut("e", modifiers: .command)

            Divider()

            blockStyleButton(.heading1, shortcut: "1")
            blockStyleButton(.heading2, shortcut: "2")
            blockStyleButton(.heading3, shortcut: "3")
            blockStyleButton(.body, shortcut: "0")

            Divider()

            blockStyleButton(.bullet, shortcut: "8")
            blockStyleButton(.numbered, shortcut: "7")
            blockStyleButton(.quote, shortcut: "9")
            blockStyleButton(.code, shortcut: "c")
        }
    }

    private func blockStyleButton(_ style: BlockStyle, shortcut: Character) -> some View {
        Button(style.displayName) { viewModel?.setBlockStyle(style) }
            .keyboardShortcut(KeyEquivalent(shortcut), modifiers: [.command, .option])
    }
}

/// Export lives in the File menu on macOS and the iPad menu bar. iPhone has
/// no menu bar and export isn't offered there yet.
struct ExportCommands: Commands {
    @FocusedValue(\.editorViewModel) var viewModel

    private var exportAvailable: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
        #else
        true
        #endif
    }

    var body: some Commands {
        CommandGroup(after: .importExport) {
            if exportAvailable {
                Button("Export as PDF…") { viewModel?.pendingExport = .pdf }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(viewModel == nil)
                Button("Export as Word…") { viewModel?.pendingExport = .docx }
                    .keyboardShortcut("e", modifiers: [.command, .shift, .option])
                    .disabled(viewModel == nil)
            }
        }
    }
}

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
