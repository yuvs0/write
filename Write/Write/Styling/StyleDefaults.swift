import Foundation

extension StyleConfiguration {
    static let `default` = StyleConfiguration(
        heading1: ElementStyle(
            fontFamily: ".AppleSystemUIFont",
            fontWeight: .regular,
            fontSize: 34,
            isItalic: false,
            relativeScale: 1.0,
            paragraphSpacingBefore: 24,
            paragraphSpacingAfter: 8
        ),
        heading2: ElementStyle(
            fontFamily: ".AppleSystemUIFont",
            fontWeight: .regular,
            fontSize: 28,
            isItalic: false,
            relativeScale: 1.0,
            paragraphSpacingBefore: 20,
            paragraphSpacingAfter: 6
        ),
        heading3: ElementStyle(
            fontFamily: ".AppleSystemUIFont",
            fontWeight: .regular,
            fontSize: 22,
            isItalic: false,
            relativeScale: 1.0,
            paragraphSpacingBefore: 16,
            paragraphSpacingAfter: 4
        ),
        heading4: ElementStyle(
            fontFamily: ".AppleSystemUIFont",
            fontWeight: .regular,
            fontSize: 20,
            isItalic: false,
            relativeScale: 1.0,
            paragraphSpacingBefore: 12,
            paragraphSpacingAfter: 4
        ),
        heading5: ElementStyle(
            fontFamily: ".AppleSystemUIFont",
            fontWeight: .regular,
            fontSize: 17,
            isItalic: false,
            relativeScale: 1.0,
            paragraphSpacingBefore: 10,
            paragraphSpacingAfter: 2
        ),
        heading6: ElementStyle(
            fontFamily: ".AppleSystemUIFont",
            fontWeight: .regular,
            fontSize: 15,
            isItalic: false,
            relativeScale: 1.0,
            paragraphSpacingBefore: 8,
            paragraphSpacingAfter: 2
        ),
        paragraph: ElementStyle(
            fontFamily: ".AppleSystemUIFont",
            fontWeight: .regular,
            fontSize: 17,
            isItalic: false,
            relativeScale: 1.0,
            paragraphSpacingBefore: 0,
            paragraphSpacingAfter: 8
        ),
        bold: InlineModifier(
            fontFamilyOverride: nil,
            fontWeightOverride: .bold,
            isItalic: nil
        ),
        italic: InlineModifier(
            fontFamilyOverride: nil,
            fontWeightOverride: nil,
            isItalic: true
        ),
        strikethrough: InlineModifier(
            fontFamilyOverride: nil,
            fontWeightOverride: nil,
            isItalic: nil
        ),
        code: ElementStyle(
            fontFamily: "SF Mono",
            fontWeight: .regular,
            fontSize: 15,
            isItalic: false,
            relativeScale: 1.0,
            paragraphSpacingBefore: 8,
            paragraphSpacingAfter: 8
        ),
        blockquote: ElementStyle(
            fontFamily: ".AppleSystemUIFont",
            fontWeight: .regular,
            fontSize: 17,
            isItalic: true,
            relativeScale: 1.0,
            paragraphSpacingBefore: 8,
            paragraphSpacingAfter: 8
        )
    )
}
