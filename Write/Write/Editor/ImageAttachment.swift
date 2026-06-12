#if os(macOS)
import AppKit
#else
import UIKit
#endif
import CoreGraphics

/// An `NSTextAttachment` that renders a document image scaled to fit the text
/// column, with the caption (when non-empty) drawn beneath it in a caption
/// style. Used for image paragraphs in the editor on both platforms (TextKit 2).
///
/// The attachment is constructed from the decoded asset bytes plus its
/// `ImageRef`. The `.writeImage` attribute on the attachment character carries
/// the same `ImageRef` as JSON, so parse/serialize never depend on the
/// attachment instance — only the editor materializes these.
final class WriteImageAttachment: NSTextAttachment {
    /// The semantic payload (filename, caption, figure flag).
    let ref: ImageRef
    /// Decoded image, retained for drawing.
    private let nativeImage: NativeImage
    /// Intrinsic pixel size of the decoded image.
    private let imageSize: CGSize

    /// Caption typography relative to the body size.
    private static let captionScale: CGFloat = 0.85
    private static let captionGap: CGFloat = 6
    private static let imageBottomPadding: CGFloat = 4

    /// Body point size used to size the caption; set by the styler/editor via
    /// the materialize pass so the caption tracks the document's body size.
    var bodyPointSize: CGFloat = 13 {
        didSet { if oldValue != bodyPointSize { invalidateRenderedImage() } }
    }

    init?(ref: ImageRef, data: Data) {
        guard let image = NativeImage(data: data) else { return nil }
        self.ref = ref
        self.nativeImage = image
        #if os(macOS)
        // NSImage.size is in points; convert to pixels via the largest rep.
        if let rep = image.representations.max(by: { $0.pixelsWide < $1.pixelsWide }),
           rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            self.imageSize = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        } else {
            self.imageSize = image.size
        }
        #else
        self.imageSize = CGSize(
            width: image.size.width * image.scale,
            height: image.size.height * image.scale
        )
        #endif
        super.init(data: nil, ofType: nil)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    private var captionPointSize: CGFloat { bodyPointSize * Self.captionScale }

    /// Drop any cached rendered image so the next layout re-renders with the
    /// current caption/size.
    private func invalidateRenderedImage() {
        image = nil
    }

    // MARK: - Layout

    /// Lay the image (and caption) out at the proposed line-fragment width.
    /// The image scales to fit the column width while preserving aspect ratio
    /// (never upscaling beyond the available width). The caption, when present,
    /// adds its measured height below.
    override func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: CGRect,
        glyphPosition position: CGPoint,
        characterIndex charIndex: Int
    ) -> CGRect {
        let available = max(lineFrag.width, 1)
        let (drawSize, captionHeight) = layout(forWidth: available)
        let totalHeight = drawSize.height + captionHeight
        // Draw from the baseline upward; a small descent keeps spacing tidy.
        return CGRect(x: 0, y: 0, width: drawSize.width, height: totalHeight)
    }

    /// Display dimensions for the image given an available width, plus the
    /// caption block height (0 when no caption).
    private func layout(forWidth available: CGFloat) -> (image: CGSize, caption: CGFloat) {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return (CGSize(width: available, height: 0), 0)
        }
        let scale = min(1, available / imageSize.width)
        let drawSize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )

        var captionHeight: CGFloat = 0
        if !ref.caption.isEmpty {
            let captionWidth = max(drawSize.width, 1)
            let bounding = (ref.caption as NSString).boundingRect(
                with: CGSize(width: captionWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: captionFont],
                context: nil
            )
            captionHeight = ceil(bounding.height) + Self.captionGap + Self.imageBottomPadding
        }
        return (drawSize, captionHeight)
    }

    private var captionFont: NativeFont {
        #if os(macOS)
        return NSFont.systemFont(ofSize: captionPointSize)
        #else
        return UIFont.systemFont(ofSize: captionPointSize)
        #endif
    }

    // MARK: - Drawing

    override func image(
        forBounds imageBounds: CGRect,
        textContainer: NSTextContainer?,
        characterIndex charIndex: Int
    ) -> NativeImage? {
        let (drawSize, captionHeight) = layout(forWidth: imageBounds.width)
        let totalSize = CGSize(
            width: max(drawSize.width, 1),
            height: max(drawSize.height + captionHeight, 1)
        )
        return renderComposite(totalSize: totalSize, imageSize: drawSize, captionHeight: captionHeight)
    }

    /// Render the image and caption into one bitmap so a single attachment cell
    /// draws both. Centered horizontally within the cell.
    private func renderComposite(
        totalSize: CGSize, imageSize drawSize: CGSize, captionHeight: CGFloat
    ) -> NativeImage? {
        #if os(macOS)
        let result = NSImage(size: totalSize)
        result.lockFocus()
        defer { result.unlockFocus() }
        // AppKit images draw bottom-up; the caption sits below the image.
        let imageRect = NSRect(
            x: (totalSize.width - drawSize.width) / 2,
            y: captionHeight,
            width: drawSize.width,
            height: drawSize.height
        )
        nativeImage.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1)
        if captionHeight > 0 {
            drawCaption(in: NSRect(x: 0, y: 0, width: totalSize.width, height: captionHeight))
        }
        return result
        #else
        let renderer = UIGraphicsImageRenderer(size: totalSize)
        return renderer.image { _ in
            let imageRect = CGRect(
                x: (totalSize.width - drawSize.width) / 2,
                y: 0,
                width: drawSize.width,
                height: drawSize.height
            )
            nativeImage.draw(in: imageRect)
            if captionHeight > 0 {
                drawCaption(in: CGRect(
                    x: 0, y: drawSize.height,
                    width: totalSize.width, height: captionHeight
                ))
            }
        }
        #endif
    }

    /// Draw the caption inside the given caption-block rect (already positioned
    /// below the image by the caller, in that platform's drawing coordinates).
    /// The visible gap between image and caption is the `captionGap` portion of
    /// the block on the image side.
    private func drawCaption(in rect: CGRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let color: NativeColor
        #if os(macOS)
        color = .secondaryLabelColor
        #else
        color = .secondaryLabel
        #endif
        let attributes: [NSAttributedString.Key: Any] = [
            .font: captionFont,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        // The caption block carries captionGap (gap to image) + text + bottom
        // padding. Inset the top so the text clears the gap.
        let drawRect = CGRect(
            x: rect.minX,
            y: rect.minY + Self.captionGap,
            width: rect.width,
            height: max(rect.height - Self.captionGap - Self.imageBottomPadding, 0)
        )
        (ref.caption as NSString).draw(
            with: drawRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
    }
}
