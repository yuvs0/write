#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct AttributedStringRenderer {
    let configuration: StyleConfiguration
    var zoomScale: CGFloat = 1.0

    func attributedString(from result: ParseResult, in text: NSString) -> NSMutableAttributedString {
        let attributed = NSMutableAttributedString(string: text as String)
        let fullRange = NSRange(location: 0, length: text.length)
        attributed.setAttributes(attributes(for: configuration.paragraph), range: fullRange)

        for node in result.nodes {
            applyBlock(node, to: attributed)
        }
        applyDelimiters(result.delimiterRanges, to: attributed)

        return attributed
    }

    func applyDelimiters(_ ranges: [NSRange], to attributedString: NSMutableAttributedString) {
        #if os(macOS)
        let hiddenFont = NSFont.systemFont(ofSize: 0.001)
        #else
        let hiddenFont = UIFont.systemFont(ofSize: 0.001)
        #endif

        let totalLength = attributedString.length
        for range in ranges {
            guard range.location >= 0, NSMaxRange(range) <= totalLength, range.length > 0 else { continue }
            attributedString.addAttributes([
                .font: hiddenFont,
                .foregroundColor: NativeColor.clear
            ], range: range)
        }
    }

    func applyBlock(_ node: MarkdownNode, to attributedString: NSMutableAttributedString) {
        let len = attributedString.length
        switch node {
        case .heading(let level, let content, let range):
            guard NSMaxRange(range) <= len else { return }
            let style = configuration.styleForHeading(level: level)
            attributedString.addAttributes(attributes(for: style), range: range)
            for inline in content {
                applyInline(inline, to: attributedString, baseStyle: style)
            }

        case .paragraph(let content, let range):
            guard NSMaxRange(range) <= len else { return }
            attributedString.addAttributes(attributes(for: configuration.paragraph), range: range)
            for inline in content {
                applyInline(inline, to: attributedString, baseStyle: configuration.paragraph)
            }

        case .blockquote(let content, let range):
            guard NSMaxRange(range) <= len else { return }
            let style = configuration.blockquote
            var attrs = attributes(for: style)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.headIndent = 20
            paragraphStyle.firstLineHeadIndent = 20
            paragraphStyle.paragraphSpacingBefore = style.paragraphSpacingBefore
            paragraphStyle.paragraphSpacing = style.paragraphSpacingAfter
            attrs[.paragraphStyle] = paragraphStyle
            attributedString.addAttributes(attrs, range: range)
            for inline in content {
                applyInline(inline, to: attributedString, baseStyle: style)
            }

        case .codeBlock(_, _, let range):
            guard NSMaxRange(range) <= len else { return }
            attributedString.addAttributes(attributes(for: configuration.code), range: range)

        case .listItem(_, let content, let range):
            guard NSMaxRange(range) <= len else { return }
            var attrs = attributes(for: configuration.paragraph)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.headIndent = 24
            paragraphStyle.firstLineHeadIndent = 8
            paragraphStyle.paragraphSpacingBefore = configuration.paragraph.paragraphSpacingBefore
            paragraphStyle.paragraphSpacing = configuration.paragraph.paragraphSpacingAfter
            attrs[.paragraphStyle] = paragraphStyle
            attributedString.addAttributes(attrs, range: range)
            for inline in content {
                applyInline(inline, to: attributedString, baseStyle: configuration.paragraph)
            }

        case .thematicBreak:
            break
        }
    }

    func safeApplyBlock(_ node: MarkdownNode, to attributedString: NSMutableAttributedString) {
        applyBlock(node, to: attributedString)
    }

    func applyInline(_ node: InlineNode, to attributedString: NSMutableAttributedString, baseStyle: ElementStyle) {
        let len = attributedString.length
        switch node {
        case .text:
            break

        case .strong(let children, let range):
            guard NSMaxRange(range) <= len else { return }
            let modifier = configuration.bold
            let weight = modifier.fontWeightOverride ?? baseStyle.fontWeight
            let family = modifier.fontFamilyOverride ?? baseStyle.fontFamily
            let isItalic = modifier.isItalic ?? baseStyle.isItalic
            let font = resolveFont(family: family, weight: weight, size: baseStyle.fontSize, italic: isItalic)
            attributedString.addAttribute(.font, value: font, range: range)
            for child in children {
                applyInline(child, to: attributedString, baseStyle: baseStyle)
            }

        case .emphasis(let children, let range):
            guard NSMaxRange(range) <= len else { return }
            let modifier = configuration.italic
            let weight = modifier.fontWeightOverride ?? baseStyle.fontWeight
            let family = modifier.fontFamilyOverride ?? baseStyle.fontFamily
            let isItalic = modifier.isItalic ?? true
            let font = resolveFont(family: family, weight: weight, size: baseStyle.fontSize, italic: isItalic)
            attributedString.addAttribute(.font, value: font, range: range)
            for child in children {
                applyInline(child, to: attributedString, baseStyle: baseStyle)
            }

        case .strikethrough(let children, let range):
            guard NSMaxRange(range) <= len else { return }
            attributedString.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            for child in children {
                applyInline(child, to: attributedString, baseStyle: baseStyle)
            }

        case .inlineCode(_, let range):
            guard NSMaxRange(range) <= len else { return }
            let font = resolveFont(
                family: configuration.code.fontFamily,
                weight: configuration.code.fontWeight,
                size: baseStyle.fontSize * 0.9,
                italic: false
            )
            attributedString.addAttribute(.font, value: font, range: range)

        case .link(_, let children, let range):
            guard NSMaxRange(range) <= len else { return }
            attributedString.addAttribute(.foregroundColor, value: NativeColor.systemBlue, range: range)
            attributedString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            for child in children {
                applyInline(child, to: attributedString, baseStyle: baseStyle)
            }
        }
    }

    func attributes(for style: ElementStyle) -> [NSAttributedString.Key: Any] {
        let font = resolveFont(
            family: style.fontFamily,
            weight: style.fontWeight,
            size: style.fontSize,
            italic: style.isItalic
        )

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacingBefore = style.paragraphSpacingBefore
        paragraphStyle.paragraphSpacing = style.paragraphSpacingAfter

        #if os(macOS)
        let textColor = NativeColor.labelColor
        #else
        let textColor = NativeColor.label
        #endif

        return [
            .font: font,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: textColor
        ]
    }

    private func resolveFont(family: String, weight: FontWeight, size: CGFloat, italic: Bool) -> NativeFont {
        let scaledSize = size * zoomScale

        #if os(macOS)
        if family == ".AppleSystemUIFont" || family.isEmpty {
            let descriptor = NSFontDescriptor.preferredFontDescriptor(forTextStyle: .body)
                .withSymbolicTraits(italic ? .italic : [])
            let baseFont = NSFont(descriptor: descriptor, size: scaledSize)
                ?? NSFont.systemFont(ofSize: scaledSize, weight: weight.nativeWeight)
            if italic {
                return NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
            }
            return NSFont.systemFont(ofSize: scaledSize, weight: weight.nativeWeight)
        }

        var traits: NSFontDescriptor.SymbolicTraits = []
        if italic { traits.insert(.italic) }
        if weight == .bold || weight == .heavy || weight == .black {
            traits.insert(.bold)
        }

        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: family,
        ]).withSymbolicTraits(traits)

        return NSFont(descriptor: descriptor, size: scaledSize)
            ?? NSFont.systemFont(ofSize: scaledSize, weight: weight.nativeWeight)
        #else
        if family == ".AppleSystemUIFont" || family.isEmpty {
            let baseFont = UIFont.systemFont(ofSize: scaledSize, weight: weight.nativeWeight)
            if italic {
                let descriptor = baseFont.fontDescriptor.withSymbolicTraits(.traitItalic)
                return descriptor.map { UIFont(descriptor: $0, size: scaledSize) } ?? baseFont
            }
            return baseFont
        }

        var traits: UIFontDescriptor.SymbolicTraits = []
        if italic { traits.insert(.traitItalic) }
        if weight == .bold || weight == .heavy || weight == .black {
            traits.insert(.traitBold)
        }

        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: family,
        ]).withSymbolicTraits(traits)

        return descriptor.map { UIFont(descriptor: $0, size: scaledSize) }
            ?? UIFont.systemFont(ofSize: scaledSize, weight: weight.nativeWeight)
        #endif
    }
}
