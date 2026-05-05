#if os(macOS)
import AppKit

typealias NativeFont = NSFont
typealias NativeColor = NSColor
typealias NativeTextView = NSTextView
typealias NativeParagraphStyle = NSMutableParagraphStyle
#else
import UIKit

typealias NativeFont = UIFont
typealias NativeColor = UIColor
typealias NativeTextView = UITextView
typealias NativeParagraphStyle = NSMutableParagraphStyle
#endif
