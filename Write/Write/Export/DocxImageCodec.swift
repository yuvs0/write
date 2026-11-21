import Foundation
import ImageIO
import CoreGraphics
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

/// Image decoding + transcoding for DOCX export. Sizes images and, for formats
/// Word can't read (HEIC/HEIF), transcodes losslessly to PNG. The original
/// bytes in the document package are never touched — transcoding happens only
/// in the produced `.docx`.
enum DocxImageCodec {
    struct Prepared {
        /// Lowercased content-type extension (png/jpeg/gif/tiff).
        let ext: String
        /// Bytes to embed (original for supported formats; PNG for HEIC).
        let bytes: Data
        let pixelWidth: Int
        let pixelHeight: Int
    }

    /// Content-type extensions Word reads natively. Anything else is transcoded
    /// to PNG.
    private static let nativeExtensions: [String: String] = [
        "png": "png",
        "jpg": "jpeg",
        "jpeg": "jpeg",
        "gif": "gif",
        "tif": "tiff",
        "tiff": "tiff",
        "bmp": "bmp",
    ]

    /// Decode `data` to measure it, and decide the embed bytes + extension.
    static func prepare(data: Data, ext: String) -> Prepared? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }

        let pixelWidth = (properties[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let pixelHeight = (properties[kCGImagePropertyPixelHeight] as? Int) ?? 0
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        let lower = ext.lowercased()
        if let nativeExt = nativeExtensions[lower] {
            // Embed the original bytes verbatim.
            return Prepared(ext: nativeExt, bytes: data, pixelWidth: pixelWidth, pixelHeight: pixelHeight)
        }

        // HEIC/HEIF or any other format: transcode to PNG for Word.
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let png = encodePNG(cgImage) else { return nil }
        return Prepared(ext: "png", bytes: png, pixelWidth: pixelWidth, pixelHeight: pixelHeight)
    }

    private static func encodePNG(_ image: CGImage) -> Data? {
        let output = NSMutableData()
        let type: CFString
        #if canImport(UniformTypeIdentifiers)
        type = UTType.png.identifier as CFString
        #else
        type = "public.png" as CFString
        #endif
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData, type, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
