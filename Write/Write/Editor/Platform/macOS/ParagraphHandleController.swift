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

        let firstLineHeight = fragment.textLineFragments.first?.typographicBounds.height
            ?? frame.height
        button.setFrameOrigin(NSPoint(
            x: origin.x - button.frame.width - 10,
            y: origin.y + frame.minY + max(0, (min(firstLineHeight, 28) - button.frame.height) / 2)
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
        for style in BlockStyle.menuStyles {
            let item = NSMenuItem(
                title: style.displayName,
                action: #selector(applyStyle(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.image = NSImage(systemSymbolName: style.symbolName, accessibilityDescription: nil)
            item.state = style == current ? .on : .off
            item.representedObject = style.rawValue
            menu.addItem(item)
        }

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: sender.bounds.maxY + 4),
            in: sender
        )
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
