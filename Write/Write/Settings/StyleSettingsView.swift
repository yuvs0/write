import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Font and formatting customization for every text style. Changes save
/// immediately and restyle all open documents live.
struct StyleSettingsView: View {
    @Bindable var store: StyleStore
    @State private var selectedElement: StyleElement = .body

    init(store: StyleStore = .shared) {
        self.store = store
    }

    enum StyleElement: String, CaseIterable, Identifiable {
        case body, heading1, heading2, heading3, heading4, heading5, heading6, quote, code

        var id: String { rawValue }

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
            }
        }

        var keyPath: WritableKeyPath<StyleConfiguration, ElementStyle> {
            switch self {
            case .body: return \.paragraph
            case .heading1: return \.heading1
            case .heading2: return \.heading2
            case .heading3: return \.heading3
            case .heading4: return \.heading4
            case .heading5: return \.heading5
            case .heading6: return \.heading6
            case .quote: return \.blockquote
            case .code: return \.code
            }
        }

        var sampleText: String {
            switch self {
            case .body: return "The quick brown fox jumps over the lazy dog."
            case .quote: return "Writing is rewriting."
            case .code: return "let words = draft.split(separator: \" \")"
            default: return "A Room of One's Own"
            }
        }
    }

    private var style: Binding<ElementStyle> {
        Binding(
            get: { store.configuration[keyPath: selectedElement.keyPath] },
            set: { store.configuration[keyPath: selectedElement.keyPath] = $0 }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("Style", selection: $selectedElement) {
                    ForEach(StyleElement.allCases) { element in
                        Text(element.displayName).tag(element)
                    }
                }

                preview
            }

            Section("Font") {
                Picker("Typeface", selection: style.fontFamily) {
                    Text("System").tag(FontResolver.systemFamilyName)
                    Divider()
                    ForEach(Self.fontFamilies, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }

                Picker("Weight", selection: style.fontWeight) {
                    ForEach(FontWeight.allCases, id: \.self) { weight in
                        Text(weight.displayName).tag(weight)
                    }
                }

                LabeledContent("Size") {
                    HStack(spacing: 8) {
                        Slider(value: style.fontSize, in: 9...64, step: 1)
                            .frame(minWidth: 120)
                        Stepper(
                            "\(Int(style.wrappedValue.fontSize)) pt",
                            value: style.fontSize,
                            in: 9...64,
                            step: 1
                        )
                        .fixedSize()
                    }
                }

                Toggle("Italic", isOn: style.isItalic)
            }

            Section("Spacing") {
                Stepper(
                    "Before paragraph: \(Int(style.wrappedValue.paragraphSpacingBefore)) pt",
                    value: style.paragraphSpacingBefore,
                    in: 0...64,
                    step: 2
                )
                Stepper(
                    "After paragraph: \(Int(style.wrappedValue.paragraphSpacingAfter)) pt",
                    value: style.paragraphSpacingAfter,
                    in: 0...64,
                    step: 2
                )
            }

            Section {
                Button("Reset All Styles to Defaults", role: .destructive) {
                    store.resetToDefaults()
                }
            }
        }
        .formStyle(.grouped)
        #if os(macOS)
        .navigationTitle("Text Styles")
        #endif
    }

    private var preview: some View {
        let element = style.wrappedValue
        let font = FontResolver.font(
            family: element.fontFamily,
            weight: element.fontWeight,
            size: element.fontSize,
            italic: element.isItalic
        )
        return Text(selectedElement.sampleText)
            .font(Font(font as CTFont))
            .lineLimit(2)
            .minimumScaleFactor(0.4)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .padding(.vertical, 4)
    }

    private static let fontFamilies: [String] = {
        #if os(macOS)
        NSFontManager.shared.availableFontFamilies
            .filter { !$0.hasPrefix(".") }
            .sorted()
        #else
        UIFont.familyNames
            .filter { !$0.hasPrefix(".") }
            .sorted()
        #endif
    }()
}

extension FontWeight {
    var displayName: String {
        switch self {
        case .thin: return "Thin"
        case .ultraLight: return "Ultra Light"
        case .light: return "Light"
        case .regular: return "Regular"
        case .medium: return "Medium"
        case .semibold: return "Semibold"
        case .bold: return "Bold"
        case .heavy: return "Heavy"
        case .black: return "Black"
        }
    }
}
