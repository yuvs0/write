#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ElementStyle: Codable, Hashable {
    var fontFamily: String
    var fontWeight: FontWeight
    var fontSize: CGFloat
    var isItalic: Bool
    var relativeScale: CGFloat
    var paragraphSpacingBefore: CGFloat
    var paragraphSpacingAfter: CGFloat
}

enum FontWeight: String, Codable, CaseIterable {
    case thin, ultraLight, light, regular, medium, semibold, bold, heavy, black

    #if os(macOS)
    var nativeWeight: NSFont.Weight {
        switch self {
        case .thin: return .thin
        case .ultraLight: return .ultraLight
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        }
    }
    #else
    var nativeWeight: UIFont.Weight {
        switch self {
        case .thin: return .thin
        case .ultraLight: return .ultraLight
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        }
    }
    #endif
}

struct InlineModifier: Codable, Hashable {
    var fontFamilyOverride: String?
    var fontWeightOverride: FontWeight?
    var isItalic: Bool?
}

struct StyleConfiguration: Codable, Hashable {
    var heading1: ElementStyle
    var heading2: ElementStyle
    var heading3: ElementStyle
    var heading4: ElementStyle
    var heading5: ElementStyle
    var heading6: ElementStyle
    var paragraph: ElementStyle
    var bold: InlineModifier
    var italic: InlineModifier
    var strikethrough: InlineModifier
    var code: ElementStyle
    var blockquote: ElementStyle

    func styleForHeading(level: Int) -> ElementStyle {
        switch level {
        case 1: return heading1
        case 2: return heading2
        case 3: return heading3
        case 4: return heading4
        case 5: return heading5
        case 6: return heading6
        default: return paragraph
        }
    }
}
