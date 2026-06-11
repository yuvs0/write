#if os(iOS)
import UIKit

/// Notion-style paragraph handle for iPad pointer hover. Lives inside the
/// text view so it scrolls with the content; fades in beside the hovered
/// paragraph and offers block style changes.
final class IOSParagraphHandleController: NSObject {
    private weak var viewModel: EditorViewModel?
    private weak var textView: UITextView?
    private let button: UIButton
    private var hoveredParagraphRange: NSRange?
    private var lastFragmentFrame: CGRect = .null

    init(viewModel: EditorViewModel, textView: UITextView) {
        self.viewModel = viewModel
        self.textView = textView

        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(
            systemName: "line.3.horizontal",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        )
        configuration.baseForegroundColor = .tertiaryLabel
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
        button = UIButton(configuration: configuration)
        button.frame = CGRect(x: 0, y: 0, width: 30, height: 26)
        button.alpha = 0
        button.showsMenuAsPrimaryAction = true

        super.init()

        button.menu = UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                completion(self?.menuActions() ?? [])
            },
        ])
        textView.addSubview(button)

        let hover = UIHoverGestureRecognizer(target: self, action: #selector(hoverChanged(_:)))
        textView.addGestureRecognizer(hover)
    }

    @objc private func hoverChanged(_ recognizer: UIHoverGestureRecognizer) {
        guard let textView else { return }
        switch recognizer.state {
        case .began, .changed:
            update(for: recognizer.location(in: textView))
        default:
            hide()
        }
    }

    private func update(for point: CGPoint) {
        guard let textView, let viewModel else { return }

        let inset = textView.textContainerInset
        let containerWidth = viewModel.textContainer.size.width
        let containerPoint = CGPoint(
            x: min(max(point.x - inset.left, 1), max(containerWidth - 1, 1)),
            y: point.y - inset.top
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
        button.frame.origin = CGPoint(
            x: inset.left - button.frame.width - 8,
            y: inset.top + frame.minY + max(0, (min(firstLineHeight, 30) - button.frame.height) / 2)
        )
        show()
    }

    func hide() {
        guard button.alpha > 0 else { return }
        lastFragmentFrame = .null
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            self.button.alpha = 0
        }
    }

    private func show() {
        guard button.alpha < 1 else { return }
        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            self.button.alpha = 1
        }
    }

    private func menuActions() -> [UIAction] {
        guard let viewModel, let paragraphRange = hoveredParagraphRange else { return [] }
        let storage = viewModel.textContentStorage.textStorage
        let current = storage?.blockStyle(at: paragraphRange.location) ?? .body

        return BlockStyle.menuStyles.map { style in
            UIAction(
                title: style.displayName,
                image: UIImage(systemName: style.symbolName),
                state: style == current ? .on : .off
            ) { [weak viewModel] _ in
                viewModel?.setBlockStyle(style, forParagraphsIn: paragraphRange)
            }
        }
    }
}
#endif
