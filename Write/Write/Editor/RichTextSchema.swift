import Foundation

/// The paragraph-level style of a block. Stored on every character of the
/// paragraph (including its trailing newline) under `.writeBlockStyle`.
nonisolated enum BlockStyle: String, CaseIterable, Codable {
    case body
    case heading1, heading2, heading3, heading4, heading5, heading6
    case quote
    case code
    case bullet
    case numbered

    var displayName: String {
        switch self {
        case .body: return "Body"
        case .heading1: return "Title"
        case .heading2: return "Heading"
        case .heading3: return "Subheading"
        case .heading4: return "Heading 4"
        case .heading5: return "Heading 5"
        case .heading6: return "Heading 6"
        case .quote: return "Quote"
        case .code: return "Code"
        case .bullet: return "Bulleted List"
        case .numbered: return "Numbered List"
        }
    }

    var symbolName: String {
        switch self {
        case .body: return "text.alignleft"
        case .heading1: return "textformat.size.larger"
        case .heading2: return "textformat.size"
        case .heading3: return "textformat.size.smaller"
        case .heading4, .heading5, .heading6: return "textformat"
        case .quote: return "text.quote"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .bullet: return "list.bullet"
        case .numbered: return "list.number"
        }
    }

    var headingLevel: Int? {
        switch self {
        case .heading1: return 1
        case .heading2: return 2
        case .heading3: return 3
        case .heading4: return 4
        case .heading5: return 5
        case .heading6: return 6
        default: return nil
        }
    }

    static func heading(level: Int) -> BlockStyle {
        switch level {
        case 1: return .heading1
        case 2: return .heading2
        case 3: return .heading3
        case 4: return .heading4
        case 5: return .heading5
        case 6: return .heading6
        default: return .body
        }
    }

    var isList: Bool { self == .bullet || self == .numbered }

    /// Styles offered directly in style pickers, grouped into sections
    /// (headings, body, lists, quote/code).
    static let menuSections: [[BlockStyle]] = [
        [.heading1, .heading2, .heading3],
        [.body],
        [.bullet, .numbered],
        [.quote, .code],
    ]

    /// Deeper heading levels, tucked behind a "More Headings" submenu so
    /// they don't clutter the pickers until someone needs them.
    static let moreHeadings: [BlockStyle] = [.heading4, .heading5, .heading6]
}

/// Character-level formatting, stored as a bitmask under `.writeInlineTraits`.
nonisolated struct InlineTraits: OptionSet, Hashable {
    let rawValue: Int

    static let bold = InlineTraits(rawValue: 1 << 0)
    static let italic = InlineTraits(rawValue: 1 << 1)
    static let underline = InlineTraits(rawValue: 1 << 2)
    static let strikethrough = InlineTraits(rawValue: 1 << 3)
    static let code = InlineTraits(rawValue: 1 << 4)
    static let superscript = InlineTraits(rawValue: 1 << 5)
    static let subscriptText = InlineTraits(rawValue: 1 << 6)
}

extension NSAttributedString.Key {
    /// String raw value of `BlockStyle`.
    static let writeBlockStyle = NSAttributedString.Key("write.blockStyle")
    /// NSNumber wrapping `InlineTraits.rawValue`. Absent means no traits.
    static let writeInlineTraits = NSAttributedString.Key("write.inlineTraits")
    /// String destination of a link.
    static let writeLink = NSAttributedString.Key("write.link")
    /// JSON-encoded `[CitationRef]` for a citation chip run.
    static let writeCitation = NSAttributedString.Key("write.citation")
    /// JSON-encoded `ImageRef` for an image attachment character. Stored
    /// alongside the `NSTextAttachment` so parse/serialize stay pure even when
    /// the asset bytes (and thus the rendered attachment) aren't available.
    static let writeImage = NSAttributedString.Key("write.image")
    /// NSNumber(true) present on every character of paragraphs inside the
    /// generated bibliography region (including the heading paragraph).
    static let writeBibliography = NSAttributedString.Key("write.bibliography")
}

// MARK: - ImageRef

/// The semantic payload of an image attachment: which asset it shows, its
/// caption (also the alt text — single source of truth), and whether it is a
/// numbered figure. Stored as JSON under `.writeImage` so the parser and
/// serializer never need the asset bytes; the editor materializes the rendered
/// `WriteImageAttachment` separately from the document's asset store.
nonisolated struct ImageRef: Hashable, Codable {
    /// Asset filename inside the package's `assets/` folder, e.g. `a1b2c3d4.png`.
    var filename: String
    /// Caption shown beneath the image and used as the markdown alt text.
    var caption: String
    /// When true the image is a numbered figure (numbering is computed at
    /// export time, never stored).
    var isFigure: Bool

    init(filename: String, caption: String = "", isFigure: Bool = false) {
        self.filename = filename
        self.caption = caption
        self.isFigure = isFigure
    }

    /// Encode to a compact, stable JSON string for storage in an attribute value.
    func encodedJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}

extension String {
    /// Decode a JSON string back to an `ImageRef`.
    func decodedImageRef() -> ImageRef? {
        guard let data = self.data(using: .utf8),
              let ref = try? JSONDecoder().decode(ImageRef.self, from: data) else {
            return nil
        }
        return ref
    }
}

extension NSAttributedString {
    /// Return the `ImageRef` stored at `location`, or nil if that position
    /// carries no image attribute.
    func imageRef(at location: Int) -> ImageRef? {
        guard location >= 0, location < length,
              let json = attribute(.writeImage, at: location, effectiveRange: nil) as? String
        else { return nil }
        return json.decodedImageRef()
    }
}

// MARK: - CitationRef JSON helpers

extension Array where Element == CitationRef {
    /// Encode to a compact, stable JSON string suitable for storage in an
    /// NSAttributedString attribute value.
    func encodedJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }
}

extension String {
    /// Decode a JSON string back to `[CitationRef]`.
    func decodedCitationRefs() -> [CitationRef]? {
        guard let data = self.data(using: .utf8),
              let refs = try? JSONDecoder().decode([CitationRef].self, from: data) else {
            return nil
        }
        return refs
    }
}

extension NSAttributedString {
    func blockStyle(at location: Int) -> BlockStyle {
        guard location >= 0, location < length,
              let raw = attribute(.writeBlockStyle, at: location, effectiveRange: nil) as? String,
              let style = BlockStyle(rawValue: raw)
        else { return .body }
        return style
    }

    func inlineTraits(at location: Int) -> InlineTraits {
        guard location >= 0, location < length,
              let number = attribute(.writeInlineTraits, at: location, effectiveRange: nil) as? NSNumber
        else { return [] }
        return InlineTraits(rawValue: number.intValue)
    }

    /// Return the `[CitationRef]` stored at `location`, or nil if that
    /// position carries no citation attribute.
    func citationRefs(at location: Int) -> [CitationRef]? {
        guard location >= 0, location < length,
              let json = attribute(.writeCitation, at: location, effectiveRange: nil) as? String
        else { return nil }
        return json.decodedCitationRefs()
    }
}

extension [NSAttributedString.Key: Any] {
    var inlineTraits: InlineTraits {
        get {
            guard let number = self[.writeInlineTraits] as? NSNumber else { return [] }
            return InlineTraits(rawValue: number.intValue)
        }
        set {
            if newValue.isEmpty {
                removeValue(forKey: .writeInlineTraits)
            } else {
                self[.writeInlineTraits] = NSNumber(value: newValue.rawValue)
            }
        }
    }

    var blockStyle: BlockStyle {
        get {
            guard let raw = self[.writeBlockStyle] as? String,
                  let style = BlockStyle(rawValue: raw) else { return .body }
            return style
        }
        set { self[.writeBlockStyle] = newValue.rawValue }
    }
}
