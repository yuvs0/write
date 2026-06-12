import SwiftUI

@main
struct WriteApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            DocumentEditorView(document: file.$document, fileURL: file.fileURL)
        }
        .commands {
            FormatCommands()
            InsertCommands()
            ExportCommands()
            ViewCommands()
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
            blockStyleButton(.heading4, shortcut: "4")
            blockStyleButton(.heading5, shortcut: "5")
            blockStyleButton(.heading6, shortcut: "6")
            blockStyleButton(.body, shortcut: "0")

            Divider()

            blockStyleButton(.bullet, shortcut: "8")
            blockStyleButton(.numbered, shortcut: "7")
            blockStyleButton(.quote, shortcut: "9")
            blockStyleButton(.code, shortcut: "c")

            Divider()

            // ⌥⌘R — insert at cursor
            Button("Insert References List at Cursor") {
                viewModel?.insertReferencesList(atEnd: false)
            }
            .keyboardShortcut("r", modifiers: [.option, .command])

            // ⌥⇧⌘R — insert at end
            Button("Insert References List at End") {
                viewModel?.insertReferencesList(atEnd: true)
            }
            .keyboardShortcut("r", modifiers: [.option, .shift, .command])

            // ⌘↩ is already handled inside the text view. Giving the same
            // shortcut to a menu item on macOS would steal it from the text
            // view, so this item has no keyboard shortcut.
            Button("Cite Link at Cursor") {
                viewModel?.citeTokenAtCaret()
            }

            #if os(iOS)
            // On iPad the split view's navigation bar is hidden, so the
            // style settings sheet is reached from the menu bar (macOS has
            // the Settings window, iPhone a navigation-bar button).
            Divider()
            Button("Text Styles…") {
                viewModel?.requestsStyleSettings = true
            }
            #endif
        }
    }

    private func blockStyleButton(_ style: BlockStyle, shortcut: Character) -> some View {
        Button(style.displayName) { viewModel?.setBlockStyle(style) }
            .keyboardShortcut(KeyEquivalent(shortcut), modifiers: [.command, .option])
    }
}

/// Insert menu (macOS + iPad menu bar): image insertion via the file open
/// panel. iPhone uses the accessory-bar photo button instead.
struct InsertCommands: Commands {
    @FocusedValue(\.editorViewModel) var viewModel

    var body: some Commands {
        CommandMenu("Insert") {
            Button("Image…") { viewModel?.pendingImageImport = true }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(viewModel == nil)
        }
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

/// View-menu toggles for the navigator sidebar and floating panels.
struct ViewCommands: Commands {
    @FocusedValue(\.editorViewModel) var viewModel

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            Toggle("Navigator", isOn: visibility(\.showsNavigator))
                .keyboardShortcut("1", modifiers: [.command, .control])
            Toggle("Formatting Bar", isOn: visibility(\.showsFormattingBar))
                .keyboardShortcut("2", modifiers: [.command, .control])
            Toggle("Statistics", isOn: visibility(\.showsStatsChip))
                .keyboardShortcut("3", modifiers: [.command, .control])
            Toggle("References", isOn: visibility(\.showsReferenceManager))
                .keyboardShortcut("4", modifiers: [.command, .control])
            Divider()
        }
    }

    private func visibility(
        _ keyPath: ReferenceWritableKeyPath<EditorViewModel, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: { viewModel?[keyPath: keyPath] ?? false },
            set: { viewModel?[keyPath: keyPath] = $0 }
        )
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
