import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

struct DocumentEditorView: View {
    @Binding var document: MarkdownDocument
    var fileURL: URL?

    @State private var viewModel: EditorViewModel
    @State private var showsSettings = false
    @State private var showsReferencesSheet = false

    init(document: Binding<MarkdownDocument>, fileURL: URL? = nil) {
        self._document = document
        self.fileURL = fileURL
        self._viewModel = State(initialValue: EditorViewModel(
            markdown: document.wrappedValue.rawText,
            referencesData: document.wrappedValue.referencesJSON,
            settingsData: document.wrappedValue.settingsJSON
        ))
    }

    var body: some View {
        content
            .onChange(of: viewModel.markdown) { _, newValue in
                document.rawText = newValue
            }
            .onChange(of: viewModel.styleStore.configuration) {
                viewModel.refreshStyle()
            }
            // Sources or style changed: restyle chips + bibliography and write
            // the updated references/settings back into the document package.
            .onChange(of: viewModel.referenceStore.revision) {
                viewModel.refreshCitations()
                document.referencesJSON = try? viewModel.referenceStore.referencesData()
                document.settingsJSON = try? viewModel.referenceStore.settingsData()
            }
            // A style switch bumps the revision via styleID's setter, but guard
            // against any path that changes it without bumping revision.
            .onChange(of: viewModel.referenceStore.styleID) {
                viewModel.refreshCitations()
                document.settingsJSON = try? viewModel.referenceStore.settingsData()
            }
            .citationErrorAlert(viewModel: viewModel)
            #if os(iOS)
            .sheet(isPresented: $showsSettings) {
                NavigationStack {
                    StyleSettingsView()
                        .navigationTitle("Text Styles")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showsSettings = false }
                            }
                        }
                }
            }
            #endif
            .fileExporter(
                isPresented: exportPresented,
                document: exportedFile,
                contentType: viewModel.pendingExport == .docx ? .docx : .pdf,
                defaultFilename: exportFilename
            ) { _ in
                viewModel.pendingExport = nil
            }
            .focusedSceneValue(\.editorViewModel, viewModel)
    }

    /// The navigator, floating formatting bar, and stats chip appear on
    /// macOS and iPad, keeping iPad close to the Mac experience. iPhone
    /// relies on the keyboard accessory bar instead.
    private var showsDesktopChrome: Bool {
        #if os(macOS)
        true
        #else
        UIDevice.current.userInterfaceIdiom == .pad
        #endif
    }

    @ViewBuilder
    private var content: some View {
        if showsDesktopChrome {
            NavigationSplitView(columnVisibility: navigatorVisibility) {
                NavigatorView(viewModel: viewModel)
                    .navigationSplitViewColumnWidth(min: 180, ideal: 230, max: 320)
            } detail: {
                editorWithChrome
                    .inspector(isPresented: $viewModel.showsReferenceManager) {
                        ReferenceManagerView(viewModel: viewModel)
                            .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
                    }
            }
        } else {
            #if os(iOS)
            editorWithChrome
                .sheet(isPresented: $showsReferencesSheet) {
                    NavigationStack {
                        ReferenceManagerView(viewModel: viewModel)
                            .navigationTitle("References")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done") { showsReferencesSheet = false }
                                }
                            }
                    }
                }
            #else
            editorWithChrome
            #endif
        }
    }

    private var navigatorVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { viewModel.showsNavigator ? .all : .detailOnly },
            set: { viewModel.showsNavigator = $0 != .detailOnly }
        )
    }

    @ViewBuilder
    private var editorWithChrome: some View {
        editorView
            .overlay(alignment: .topLeading) { citationPopoverAnchor }
            #if os(macOS)
            .background {
                VisualEffectBackground()
                    .ignoresSafeArea()
            }
            #endif
            .overlay(alignment: .bottom) {
                if showsDesktopChrome, viewModel.showsFormattingBar {
                    CollapsibleToolbar(viewModel: viewModel)
                        .padding(.bottom, 16)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if showsDesktopChrome, viewModel.showsStatsChip {
                    StatsChip(viewModel: viewModel)
                        .padding(.bottom, 16)
                        .padding(.trailing, 16)
                }
            }
            #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsSettings = true
                    } label: {
                        Label("Style Settings", systemImage: "textformat.alt")
                    }
                }
                if !showsDesktopChrome {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showsReferencesSheet = true
                        } label: {
                            Label("References", systemImage: "books.vertical")
                        }
                    }
                }
            }
            #endif
    }

    /// A zero-size anchor that hosts the citation popover, positioned at the
    /// chip's rect within the editor. Driven by `pendingPopoverChipRange`.
    @ViewBuilder
    private var citationPopoverAnchor: some View {
        let presented = Binding(
            get: { viewModel.pendingPopoverChipRange != nil },
            set: { if !$0 { viewModel.pendingPopoverChipRange = nil } }
        )
        if let chipRange = viewModel.pendingPopoverChipRange,
           let rect = viewModel.viewRect(forCharacterRange: chipRange) {
            Color.clear
                .frame(width: 1, height: 1)
                .popover(
                    isPresented: presented,
                    attachmentAnchor: .rect(.rect(rect)),
                    arrowEdge: .bottom
                ) {
                    CitationPopover(viewModel: viewModel, chipRange: chipRange) {
                        viewModel.pendingPopoverChipRange = nil
                    }
                    .presentationCompactAdaptation(.popover)
                }
        }
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

    private var exportPresented: Binding<Bool> {
        Binding(
            get: { viewModel.pendingExport != nil },
            set: { presented in
                if !presented { viewModel.pendingExport = nil }
            }
        )
    }

    private var exportedFile: ExportedFile? {
        guard let format = viewModel.pendingExport,
              let data = viewModel.exportData(for: format) else { return nil }
        return ExportedFile(data: data)
    }

    private var exportFilename: String {
        let base = fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
        switch viewModel.pendingExport {
        case .docx: return base + ".docx"
        default: return base + ".pdf"
        }
    }
}

// MARK: - Citation error surfacing

private extension View {
    /// Surfaces `viewModel.citationError` as a dismissible alert.
    func citationErrorAlert(viewModel: EditorViewModel) -> some View {
        let presented = Binding(
            get: { viewModel.citationError != nil },
            set: { if !$0 { viewModel.citationError = nil } }
        )
        return alert("Citation", isPresented: presented) {
            Button("OK", role: .cancel) { viewModel.citationError = nil }
        } message: {
            Text(viewModel.citationError ?? "")
        }
    }
}
