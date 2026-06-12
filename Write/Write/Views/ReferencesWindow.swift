import SwiftUI

/// Live editor view models keyed by document URL, so auxiliary scenes (the
/// iPad references window) can reach the document they belong to.
@Observable
final class DocumentRegistry {
    static let shared = DocumentRegistry()

    private struct WeakModel {
        weak var model: EditorViewModel?
    }

    private var models: [URL: WeakModel] = [:]
    /// Bumped on every register/unregister so windows re-resolve lookups.
    private(set) var revision = 0

    func register(_ model: EditorViewModel, for url: URL) {
        models[url.standardizedFileURL] = WeakModel(model: model)
        revision += 1
    }

    func unregister(url: URL) {
        models.removeValue(forKey: url.standardizedFileURL)
        revision += 1
    }

    func model(for url: URL) -> EditorViewModel? {
        models[url.standardizedFileURL]?.model
    }
}

#if os(iOS)
/// The references manager as its own window scene: on iPadOS it opens as a
/// second window the user can place in Split View or Slide Over alongside
/// the document.
struct ReferencesWindowScene: Scene {
    var body: some Scene {
        WindowGroup("References", id: "references", for: URL.self) { $url in
            ReferencesWindowContent(url: url)
        }
    }
}

private struct ReferencesWindowContent: View {
    let url: URL?

    var body: some View {
        let registry = DocumentRegistry.shared
        // Reading revision re-resolves the lookup when documents open/close.
        let _ = registry.revision
        NavigationStack {
            Group {
                if let url, let viewModel = registry.model(for: url) {
                    ReferenceManagerView(viewModel: viewModel)
                } else {
                    ContentUnavailableView(
                        "No Document",
                        systemImage: "books.vertical",
                        description: Text("Open the document this references window belongs to.")
                    )
                }
            }
            .navigationTitle(url.map { "References — \($0.deletingPathExtension().lastPathComponent)" }
                ?? "References")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
#endif
