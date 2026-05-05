import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let writeDocument = UTType(exportedAs: "com.yuvrajsethia.write-document")
}

struct MarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.writeDocument] }

    var rawText: String
    var savedText: String

    init(rawText: String = "") {
        self.rawText = rawText
        self.savedText = rawText
    }

    init(configuration: ReadConfiguration) throws {
        guard let wrappers = configuration.file.fileWrappers else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let autosaveData = wrappers["autosave.md"]?.regularFileContents
        let contentData = wrappers["content.md"]?.regularFileContents

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
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let directory = FileWrapper(directoryWithFileWrappers: [:])

        let contentData = rawText.data(using: .utf8) ?? Data()
        directory.addRegularFile(withContents: contentData, preferredFilename: "content.md")

        return directory
    }
}
