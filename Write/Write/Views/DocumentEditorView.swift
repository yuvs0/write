import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
#if os(iOS)
import UIKit
#endif

struct DocumentEditorView: View {
    @Binding var document: MarkdownDocument
    var fileURL: URL?

    @State private var viewModel: EditorViewModel
    @State private var showsSettings = false
    @State private var showsReferencesSheet = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showsPhotoPicker = false

    init(document: Binding<MarkdownDocument>, fileURL: URL? = nil) {
        self._document = document
        self.fileURL = fileURL
        self._viewModel = State(initialValue: EditorViewModel(
            markdown: document.wrappedValue.rawText,
            referencesData: document.wrappedValue.referencesJSON,
            settingsData: document.wrappedValue.settingsJSON,
            assets: document.wrappedValue.assets
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
            // Image assets changed: write the updated set into the document
            // package (mirrors the references write-back).
            .onChange(of: viewModel.assetsRevision) {
                document.assets = viewModel.assets
            }
            .citationErrorAlert(viewModel: viewModel)
            #if os(iOS)
            .onChange(of: viewModel.requestsStyleSettings) { _, requested in
                if requested {
                    showsSettings = true
                    viewModel.requestsStyleSettings = false
                }
            }
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
            // Insert → Image… (macOS / iPad menu bar): import an image file.
            .fileImporter(
                isPresented: imageImportPresented,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false
            ) { result in
                viewModel.pendingImageImport = false
                if case .success(let urls) = result, let url = urls.first {
                    importImageFile(url)
                }
            }
            // iPhone photo picker (presented from the accessory bar button).
            .photosPicker(
                isPresented: $showsPhotoPicker,
                selection: $photoItem,
                matching: .images,
                preferredItemEncoding: .current
            )
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { await loadPickedPhoto(item) }
            }
            .onChange(of: viewModel.requestsPhotoPicker) { _, requested in
                if requested {
                    showsPhotoPicker = true
                    viewModel.requestsPhotoPicker = false
                }
            }
            .overlay(alignment: .topLeading) { imagePopoverAnchor }
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
                    #if os(iOS)
                    // DocumentGroup already provides the iPad navigation bar
                    // (back, filename, rename). The split view's own bar
                    // would stack a second one below it, eating a quarter of
                    // the screen and surfacing leaked titles.
                    .toolbar(.hidden, for: .navigationBar)
                    #endif
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
                EditorBackground()
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
            // iPad floats a sidebar toggle (its split-view bar is hidden);
            // text style settings live in the menu bar there. iPhone keeps
            // navigation-bar buttons.
            .overlay(alignment: .topLeading) {
                if showsDesktopChrome {
                    Button {
                        withAnimation { viewModel.showsNavigator.toggle() }
                    } label: {
                        Image(systemName: "sidebar.leading")
                            .font(.system(size: 15, weight: .medium))
                            .frame(width: 36, height: 36)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .padding(.top, 12)
                    .padding(.leading, 14)
                }
            }
            .toolbar {
                if !showsDesktopChrome {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showsSettings = true
                        } label: {
                            Label("Style Settings", systemImage: "textformat.alt")
                        }
                    }
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
           let rect = viewModel.viewportRect(forCharacterRange: chipRange) {
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

    private var imageImportPresented: Binding<Bool> {
        Binding(
            get: { viewModel.pendingImageImport },
            set: { presented in
                if !presented { viewModel.pendingImageImport = false }
            }
        )
    }

    /// A zero-size anchor hosting the image caption popover, positioned at the
    /// image attachment's rect. Driven by `pendingImagePopoverRange`.
    @ViewBuilder
    private var imagePopoverAnchor: some View {
        let presented = Binding(
            get: { viewModel.pendingImagePopoverRange != nil },
            set: { if !$0 { viewModel.pendingImagePopoverRange = nil } }
        )
        if let range = viewModel.pendingImagePopoverRange,
           let rect = viewModel.viewportRect(forCharacterRange: range) {
            Color.clear
                .frame(width: 1, height: 1)
                .popover(
                    isPresented: presented,
                    attachmentAnchor: .rect(.rect(rect)),
                    arrowEdge: .bottom
                ) {
                    ImagePopover(viewModel: viewModel, imageRange: range) {
                        viewModel.pendingImagePopoverRange = nil
                    }
                    .presentationCompactAdaptation(.popover)
                }
        }
    }

    /// Read an image file (Insert → Image…) and insert it at the caret.
    private func importImageFile(_ url: URL) {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        let ext = url.pathExtension
        viewModel.insertImage(data: data, fileExtension: ext)
    }

    /// Load a picked photo's Data (preserving original format) and insert it.
    private func loadPickedPhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        // Infer the extension from the picker's supplied content types.
        let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "png"
        viewModel.insertImage(data: data, fileExtension: ext)
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
