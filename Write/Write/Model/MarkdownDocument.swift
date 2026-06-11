import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let writeDocument = UTType(exportedAs: "com.yuvrajsethia.write-document")
}

struct MarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.writeDocument] }

    var rawText: String
    var savedText: String
    var referencesJSON: Data?
    var settingsJSON: Data?

    init(rawText: String = "") {
        self.rawText = rawText
        self.savedText = rawText
    }

    init(configuration: ReadConfiguration) throws {
        guard let wrappers = configuration.file.fileWrappers else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let autosaveData = wrappers["autosave.md"]?.regularFileContents
        let contentData  = wrappers["content.md"]?.regularFileContents

        if let autosaveData, let autosaveText = String(data: autosaveData, encoding: .utf8) {
            self.rawText = autosaveText
        } else if let contentData, let contentText = String(data: contentData, encoding: .utf8) {
            self.rawText = contentText
        } else {
            self.rawText = ""
        }

        if let contentData, let contentText = String(data: contentData, encoding: .utf8) {
            self.savedText = contentText
        } else {
            self.savedText = self.rawText
        }

        self.referencesJSON = wrappers["references.json"]?.regularFileContents
        self.settingsJSON   = wrappers["settings.json"]?.regularFileContents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let contentData = (rawText.data(using: .utf8)) ?? Data()
        return Self.mergedFileWrapper(
            existing: configuration.existingFile,
            contentMD: contentData,
            referencesJSON: referencesJSON,
            settingsJSON: settingsJSON
        )
    }

    /// Merges updated content into an existing directory wrapper (or builds
    /// a fresh one), preserving any child wrappers not owned by this layer.
    ///
    /// Rules:
    /// - Always replace `content.md` with `contentMD`.
    /// - Replace `references.json` / `settings.json` when the corresponding
    ///   `Data?` parameter is non-nil; leave untouched when nil.
    /// - All other child wrappers (e.g. `assets/`, `custom.txt`) pass through.
    nonisolated static func mergedFileWrapper(
        existing: FileWrapper?,
        contentMD: Data,
        referencesJSON: Data?,
        settingsJSON: Data?
    ) -> FileWrapper {
        let directory: FileWrapper

        if let existing, existing.isDirectory {
            directory = existing
        } else {
            directory = FileWrapper(directoryWithFileWrappers: [:])
        }

        // Helper: replace or add a named regular-file child.
        func replace(named filename: String, with data: Data) {
            if let old = directory.fileWrappers?[filename] {
                directory.removeFileWrapper(old)
            }
            directory.addRegularFile(withContents: data, preferredFilename: filename)
        }

        replace(named: "content.md", with: contentMD)

        if let data = referencesJSON {
            replace(named: "references.json", with: data)
        }

        if let data = settingsJSON {
            replace(named: "settings.json", with: data)
        }

        return directory
    }
}
