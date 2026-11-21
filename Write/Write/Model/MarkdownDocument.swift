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
    /// Image assets keyed by filename (e.g. `a1b2c3d4.png`), stored byte-for-byte
    /// in the package's `assets/` folder. Originals are never recompressed.
    var assets: [String: Data]

    init(rawText: String = "") {
        self.rawText = rawText
        self.savedText = rawText
        self.assets = [:]
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

        // Load every regular file inside the `assets/` directory wrapper,
        // keyed by filename, preserving the bytes verbatim.
        var assets: [String: Data] = [:]
        if let assetsWrapper = wrappers["assets"], assetsWrapper.isDirectory,
           let children = assetsWrapper.fileWrappers {
            for (name, child) in children {
                if let data = child.regularFileContents {
                    assets[name] = data
                }
            }
        }
        self.assets = assets
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let contentData = (rawText.data(using: .utf8)) ?? Data()
        return Self.mergedFileWrapper(
            existing: configuration.existingFile,
            contentMD: contentData,
            referencesJSON: referencesJSON,
            settingsJSON: settingsJSON,
            assets: assets
        )
    }

    /// Merges updated content into an existing directory wrapper (or builds
    /// a fresh one), preserving any child wrappers not owned by this layer.
    ///
    /// Rules:
    /// - Always replace `content.md` with `contentMD`.
    /// - Replace `references.json` / `settings.json` when the corresponding
    ///   `Data?` parameter is non-nil; leave untouched when nil.
    /// - Rewrite the `assets/` folder from `assets` (the dict was loaded from
    ///   that folder, so replacing it wholesale is lossless; an empty dict
    ///   removes the folder).
    /// - All other child wrappers (e.g. `custom.txt`) pass through.
    nonisolated static func mergedFileWrapper(
        existing: FileWrapper?,
        contentMD: Data,
        referencesJSON: Data?,
        settingsJSON: Data?,
        assets: [String: Data] = [:]
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

        // Rewrite the assets folder from the dict. Remove the old folder first
        // so deletions propagate; only re-add when there are assets to store.
        if let oldAssets = directory.fileWrappers?["assets"] {
            directory.removeFileWrapper(oldAssets)
        }
        if !assets.isEmpty {
            var children: [String: FileWrapper] = [:]
            for (name, data) in assets {
                let child = FileWrapper(regularFileWithContents: data)
                child.preferredFilename = name
                children[name] = child
            }
            let assetsWrapper = FileWrapper(directoryWithFileWrappers: children)
            assetsWrapper.preferredFilename = "assets"
            directory.addFileWrapper(assetsWrapper)
        }

        return directory
    }
}
