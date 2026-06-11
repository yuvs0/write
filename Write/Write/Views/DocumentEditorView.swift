import SwiftUI
import UniformTypeIdentifiers

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
        editorView
            #if os(macOS)
            .background {
                VisualEffectBackground()
                    .ignoresSafeArea()
            }
            #endif
            .onChange(of: viewModel.markdown) { _, newValue in
                document.rawText = newValue
            }
            .onChange(of: viewModel.styleStore.configuration) {
                viewModel.refreshStyle()
            }
            #if os(macOS)
            .overlay(alignment: .bottom) {
                CollapsibleToolbar(viewModel: viewModel)
                    .padding(.bottom, 16)
            }
            #else
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
