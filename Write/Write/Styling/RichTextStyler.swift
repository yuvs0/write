#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Resolves the editor's semantic attributes (`.writeBlockStyle`,
/// `.writeInlineTraits`) into visual attributes — fonts, colors, paragraph
/// styles, and list markers — according to the user's style configuration.
struct RichTextStyler {
    var configuration: StyleConfiguration
    var zoomScale: CGFloat = 1.0
    /// Export rendering uses fixed colors instead of dynamic label colors.
    var forExport: Bool = false

    func elementStyle(for blockStyle: BlockStyle) -> ElementStyle {
        switch blockStyle {
        case .body, .bullet, .numbered: return configuration.paragraph
        case .heading1: return configuration.heading1
        case .heading2: return configuration.heading2
        case .heading3: return configuration.heading3
        case .heading4: return configuration.heading4
        case .heading5: return configuration.heading5
        case .heading6: return configuration.heading6
        case .quote: return configuration.blockquote
        case .code: return configuration.code
        }
    }

    // MARK: - Applying styles

    /// Re-resolves visual attributes for the paragraphs intersecting `range`
    /// (the whole string when nil). Semantic attributes are left untouched.
    func applyStyles(to storage: NSMutableAttributedString, in range: NSRange? = nil) {
        let text = storage.string as NSString
        guard text.length > 0 else { return }

        var target = range.map { text.paragraphRange(for: $0) }
            ?? NSRange(location: 0, length: text.length)

        // List numbering depends on neighbors, so widen to cover any
        // adjacent list paragraphs.
        target = extendToListRuns(target, in: storage)

        var paragraphs: [NSRange] = []
        var location = target.location
        while location < NSMaxRange(target) {
            let paragraph = text.paragraphRange(for: NSRange(location: location, length: 0))
            paragraphs.append(paragraph)
            location = NSMaxRange(paragraph)
            if paragraph.length == 0 { break }
        }
        if paragraphs.isEmpty {
            paragraphs = [target]
        }

        var numberedItem = 1
        var previousStyle: BlockStyle?

        for paragraph in paragraphs {
            let blockStyle = storage.blockStyle(at: paragraph.location)
            if blockStyle == .numbered {
                numberedItem = (previousStyle == .numbered) ? numberedItem + 1 : startingNumber(
                    forParagraphAt: paragraph.location, in: storage
                )
            }
            applyParagraphStyles(
                to: storage,
                paragraph: paragraph,
                blockStyle: blockStyle,
                numberedItem: numberedItem
            )
            previousStyle = blockStyle
        }
    }

    /// Visual typing attributes for the given semantic state, used to keep
    /// `typingAttributes` in sync at the insertion point.
    func typingAttributes(blockStyle: BlockStyle, traits: InlineTraits) -> [NSAttributedString.Key: Any] {
        var attributes = visualAttributes(blockStyle: blockStyle, traits: traits, link: nil)
        attributes[.writeBlockStyle] = blockStyle.rawValue
        attributes.inlineTraits = traits
        attributes[.paragraphStyle] = paragraphStyle(for: blockStyle, numberedItem: 1)
        return attributes
    }

    // MARK: - Internals

    private func extendToListRuns(_ range: NSRange, in storage: NSMutableAttributedString) -> NSRange {
        let text = storage.string as NSString
        var result = range

        while result.location > 0 {
            let previous = text.paragraphRange(for: NSRange(location: result.location - 1, length: 0))
            guard storage.blockStyle(at: previous.location).isList else { break }
            result = NSUnionRange(result, previous)
        }
        while NSMaxRange(result) < text.length {
            let next = text.paragraphRange(for: NSRange(location: NSMaxRange(result), length: 0))
            guard storage.blockStyle(at: next.location).isList else { break }
            result = NSUnionRange(result, next)
            if next.length == 0 { break }
        }
        return result
    }

    private func startingNumber(forParagraphAt location: Int, in storage: NSMutableAttributedString) -> Int {
        let text = storage.string as NSString
        var number = 1
        var cursor = location
        while cursor > 0 {
            let previous = text.paragraphRange(for: NSRange(location: cursor - 1, length: 0))
            guard storage.blockStyle(at: previous.location) == .numbered else { break }
            number += 1
            cursor = previous.location
        }
        return number
    }

    private func applyParagraphStyles(
        to storage: NSMutableAttributedString,
        paragraph: NSRange,
        blockStyle: BlockStyle,
        numberedItem: Int
    ) {
        guard paragraph.length > 0 else { return }

        let paragraphStyle = self.paragraphStyle(for: blockStyle, numberedItem: numberedItem)
        storage.addAttribute(.paragraphStyle, value: paragraphStyle, range: paragraph)

        storage.enumerateAttributes(in: paragraph, options: []) { attrs, runRange, _ in
            let traits = attrs.inlineTraits
            let link = attrs[.writeLink] as? String
            var visual = visualAttributes(blockStyle: blockStyle, traits: traits, link: link)
            visual[.paragraphStyle] = paragraphStyle

            // Clear stale visual attributes before applying fresh ones.
            storage.removeAttribute(.underlineStyle, range: runRange)
            storage.removeAttribute(.strikethroughStyle, range: runRange)
            storage.removeAttribute(.backgroundColor, range: runRange)
            storage.removeAttribute(.baselineOffset, range: runRange)
            storage.addAttributes(visual, range: runRange)
        }
    }

    private func visualAttributes(
        blockStyle: BlockStyle,
        traits: InlineTraits,
        link: String?
    ) -> [NSAttributedString.Key: Any] {
        let base = elementStyle(for: blockStyle)
        var attributes: [NSAttributedString.Key: Any] = [:]

        var family = base.fontFamily
        var weight = base.fontWeight
        var italic = base.isItalic
        var size = base.fontSize

        if traits.contains(.bold) {
            weight = configuration.bold.fontWeightOverride ?? .bold
            if let familyOverride = configuration.bold.fontFamilyOverride { family = familyOverride }
            if let italicOverride = configuration.bold.isItalic { italic = italicOverride }
        }
        if traits.contains(.italic) {
            italic = configuration.italic.isItalic ?? true
            if let familyOverride = configuration.italic.fontFamilyOverride { family = familyOverride }
            if let weightOverride = configuration.italic.fontWeightOverride { weight = weightOverride }
        }
        if traits.contains(.code) {
            family = configuration.code.fontFamily
            size *= 0.9
            attributes[.backgroundColor] = codeBackgroundColor
        }
        if traits.contains(.superscript) || traits.contains(.subscriptText) {
            let offset = size * 0.33 * zoomScale
            attributes[.baselineOffset] = traits.contains(.superscript) ? offset : -offset
            size *= 0.7
        }

        attributes[.font] = FontResolver.font(
            family: family, weight: weight, size: size * zoomScale, italic: italic
        )

        if traits.contains(.underline) {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if traits.contains(.strikethrough) {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }

        if link != nil {
            attributes[.foregroundColor] = linkColor
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        } else {
            attributes[.foregroundColor] = textColor(for: blockStyle)
        }

        return attributes
    }

    private func paragraphStyle(for blockStyle: BlockStyle, numberedItem: Int) -> NSParagraphStyle {
        let base = elementStyle(for: blockStyle)
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = base.paragraphSpacingBefore * zoomScale
        style.paragraphSpacing = base.paragraphSpacingAfter * zoomScale
        style.lineHeightMultiple = 1.12

        switch blockStyle {
        case .quote:
            style.headIndent = 20 * zoomScale
            style.firstLineHeadIndent = 20 * zoomScale
        case .bullet, .numbered:
            let indent = 28 * zoomScale
            style.headIndent = indent
            style.firstLineHeadIndent = indent
            let format: NSTextList.MarkerFormat = blockStyle == .bullet ? .disc : .decimal
            let list = NSTextList(markerFormat: format, options: 0)
            list.startingItemNumber = numberedItem
            style.textLists = [list]
        default:
            break
        }
        return style
    }

    // MARK: - Colors

    private func textColor(for blockStyle: BlockStyle) -> NativeColor {
        if forExport {
            return blockStyle == .quote ? NativeColor.darkGray : NativeColor.black
        }
        #if os(macOS)
        return blockStyle == .quote ? .secondaryLabelColor : .labelColor
        #else
        return blockStyle == .quote ? .secondaryLabel : .label
        #endif
    }

    private var linkColor: NativeColor {
        forExport ? NativeColor.systemBlue : NativeColor.systemBlue
    }

    private var codeBackgroundColor: NativeColor {
        if forExport {
            return NativeColor(white: 0.94, alpha: 1)
        }
        #if os(macOS)
        return NativeColor.labelColor.withAlphaComponent(0.07)
        #else
        return NativeColor.label.withAlphaComponent(0.07)
        #endif
    }
}

/// Shared font resolution for styles and settings previews.
enum FontResolver {
    static let systemFamilyName = ".AppleSystemUIFont"

    static func font(family: String, weight: FontWeight, size: CGFloat, italic: Bool) -> NativeFont {
        #if os(macOS)
        if family == systemFamilyName || family.isEmpty {
            var font = NSFont.systemFont(ofSize: size, weight: weight.nativeWeight)
            if italic {
                font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            }
            return font
        }

        var traits: NSFontDescriptor.SymbolicTraits = []
        if italic { traits.insert(.italic) }
        if weight == .bold || weight == .heavy || weight == .black { traits.insert(.bold) }

        var descriptor = NSFontDescriptor(fontAttributes: [.family: family])
        descriptor = descriptor.withSymbolicTraits(traits)
        if let font = NSFont(descriptor: descriptor, size: size) {
            return font
        }
        return NSFont.systemFont(ofSize: size, weight: weight.nativeWeight)
        #else
        if family == systemFamilyName || family.isEmpty {
            let font = UIFont.systemFont(ofSize: size, weight: weight.nativeWeight)
            guard italic else { return font }
            let descriptor = font.fontDescriptor.withSymbolicTraits(
                font.fontDescriptor.symbolicTraits.union(.traitItalic)
            )
            return descriptor.map { UIFont(descriptor: $0, size: size) } ?? font
        }

        var traits: UIFontDescriptor.SymbolicTraits = []
        if italic { traits.insert(.traitItalic) }
        if weight == .bold || weight == .heavy || weight == .black { traits.insert(.traitBold) }

        let descriptor = UIFontDescriptor(fontAttributes: [.family: family])
        if let resolved = descriptor.withSymbolicTraits(traits) {
            return UIFont(descriptor: resolved, size: size)
        }
        return UIFont(descriptor: descriptor, size: size)
        #endif
    }
}
