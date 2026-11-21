#if os(macOS)
import AppKit

/// The Notion-style handle that fades in beside the hovered paragraph and
/// offers block style changes. Lives inside the text view so it scrolls
/// with the content.
final class ParagraphHandleController: NSObject {
    private weak var viewModel: EditorViewModel?
    private weak var textView: WriteTextView?
    private let button: NSButton
    private var hoveredParagraphRange: NSRange?
    private var lastFragmentFrame: CGRect = .null

    init(viewModel: EditorViewModel, textView: WriteTextView) {
        self.viewModel = viewModel
        self.textView = textView

        button = NSButton(frame: NSRect(x: 0, y: 0, width: 26, height: 22))
        button.bezelStyle = .accessoryBarAction
        button.isBordered = true
        button.showsBorderOnlyWhileMouseInside = true
        button.image = NSImage(
            systemSymbolName: "line.3.horizontal",
            accessibilityDescription: "Paragraph style"
        )?.withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
        button.contentTintColor = .tertiaryLabelColor
        button.alphaValue = 0
        button.toolTip = "Paragraph style"

        super.init()

        button.target = self
        button.action = #selector(presentMenu(_:))
        textView.addSubview(button)
    }

    // MARK: - Hover tracking

    func mouseMoved(to point: NSPoint?) {
        guard let textView, let viewModel else { return }
        guard let point else {
            hide()
            return
        }

        let origin = textView.textContainerOrigin
        let containerSize = viewModel.textContainer.size
        let containerPoint = CGPoint(
            x: min(max(point.x - origin.x, 1), max(containerSize.width - 1, 1)),
            y: point.y - origin.y
        )

        guard let fragment = viewModel.textLayoutManager.textLayoutFragment(for: containerPoint) else {
            hide()
            return
        }

        let frame = fragment.layoutFragmentFrame
        guard frame != lastFragmentFrame else { return }
        lastFragmentFrame = frame

        let contentStorage = viewModel.textContentStorage
        let documentStart = contentStorage.documentRange.location
        let range = fragment.rangeInElement
        let start = contentStorage.offset(from: documentStart, to: range.location)
        let length = contentStorage.offset(from: range.location, to: range.endLocation)
        hoveredParagraphRange = NSRange(location: start, length: length)

        // Center the handle on the cap-height band of the first line so it
        // tracks the text baseline whatever the paragraph's font size.
        var centerY = frame.minY + frame.height / 2
        if let firstLine = fragment.textLineFragments.first {
            let baseline = frame.minY + firstLine.typographicBounds.minY + firstLine.glyphOrigin.y
            let font = contentStorage.textStorage.flatMap {
                $0.length > start ? $0.attribute(.font, at: start, effectiveRange: nil) as? NSFont : nil
            }
            let capHeight = font?.capHeight ?? 10
            centerY = baseline - capHeight / 2
        }

        button.setFrameOrigin(NSPoint(
            x: max(2, origin.x - button.frame.width - 8),
            y: (origin.y + centerY - button.frame.height / 2).rounded()
        ))
        show()
    }

    func hide() {
        guard button.alphaValue > 0 else { return }
        lastFragmentFrame = .null
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            button.animator().alphaValue = 0
        }
    }

    private func show() {
        guard button.alphaValue < 1 else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            button.animator().alphaValue = 1
        }
    }

    // MARK: - Style menu

    @objc private func presentMenu(_ sender: NSButton) {
        guard let viewModel, let paragraphRange = hoveredParagraphRange else { return }

        let storage = viewModel.textContentStorage.textStorage
        let current = storage?.blockStyle(at: paragraphRange.location) ?? .body

        let menu = NSMenu()
        menu.autoenablesItems = false
        for (sectionIndex, section) in BlockStyle.menuSections.enumerated() {
            if sectionIndex > 0 {
                menu.addItem(.separator())
            }
            for style in section {
                menu.addItem(menuItem(for: style, current: current))
            }
            if sectionIndex == 0 {
                let moreItem = NSMenuItem(title: "More Headings", action: nil, keyEquivalent: "")
                moreItem.state = BlockStyle.moreHeadings.contains(current) ? .on : .off
                let submenu = NSMenu()
                submenu.autoenablesItems = false
                for style in BlockStyle.moreHeadings {
                    submenu.addItem(menuItem(for: style, current: current))
                }
                moreItem.submenu = submenu
                menu.addItem(moreItem)
            }
        }

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: sender.bounds.maxY + 4),
            in: sender
        )
    }

    private func menuItem(for style: BlockStyle, current: BlockStyle) -> NSMenuItem {
        let item = NSMenuItem(
            title: style.displayName,
            action: #selector(applyStyle(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.image = NSImage(systemSymbolName: style.symbolName, accessibilityDescription: nil)
        item.state = style == current ? .on : .off
        item.representedObject = style.rawValue
        return item
    }

    @objc private func applyStyle(_ sender: NSMenuItem) {
        guard let viewModel,
              let raw = sender.representedObject as? String,
              let style = BlockStyle(rawValue: raw),
              let paragraphRange = hoveredParagraphRange
        else { return }
        viewModel.setBlockStyle(style, forParagraphsIn: paragraphRange)
    }
}
#endif
