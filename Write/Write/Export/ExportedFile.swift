import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let docx = UTType("org.openxmlformats.wordprocessingml.document")
        ?? UTType(filenameExtension: "docx", conformingTo: .data)!
}

/// Transient wrapper handed to `fileExporter` for PDF and DOCX exports.
struct ExportedFile: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf, .docx] }
    static var writableContentTypes: [UTType] { [.pdf, .docx] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
