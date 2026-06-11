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

    init(document: Binding<MarkdownDocument>, fileURL: URL? = nil) {
        self._document = document
        self.fileURL = fileURL
        self._viewModel = State(initialValue: EditorViewModel(markdown: document.wrappedValue.rawText))
    }

    var body: some View {
        content
            .onChange(of: viewModel.markdown) { _, newValue in
                document.rawText = newValue
            }
            .onChange(of: viewModel.styleStore.configuration) {
                viewModel.refreshStyle()
            }
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
            }
        } else {
            editorWithChrome
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
            }
            #endif
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
