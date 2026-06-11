import Foundation

/// The paragraph-level style of a block. Stored on every character of the
/// paragraph (including its trailing newline) under `.writeBlockStyle`.
enum BlockStyle: String, CaseIterable, Codable {
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
struct InlineTraits: OptionSet, Hashable {
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
