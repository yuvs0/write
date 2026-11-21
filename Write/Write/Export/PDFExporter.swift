#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Renders the editor's semantic attributed string into a paginated PDF
/// using the document's configured styles.
struct PDFExporter {
    let configuration: StyleConfiguration
    /// Image assets keyed by filename, used to draw image attachments.
    let assets: [String: Data]

    init(configuration: StyleConfiguration, assets: [String: Data] = [:]) {
        self.configuration = configuration
        self.assets = assets
    }

    /// US Letter for Letter-paper regions, A4 elsewhere.
    private var pageSize: CGSize {
        let letterRegions: Set<String> = ["US", "CA", "MX", "PH"]
        if let region = Locale.current.region?.identifier, letterRegions.contains(region) {
            return CGSize(width: 612, height: 792)
        }
        return CGSize(width: 595, height: 842)
    }

    private let pageMargin: CGFloat = 72

    func pdfData(from semantic: NSAttributedString) -> Data? {
        let content = NSMutableAttributedString(attributedString: semantic)
        // Print sizing: body renders at 11pt and everything else scales
        // proportionally, regardless of the on-screen editing sizes.
        let scale = DocxExporter.exportBodyPointSize / max(configuration.paragraph.fontSize, 1)
        var styler = RichTextStyler(configuration: configuration, zoomScale: scale)
        styler.forExport = true
        styler.applyStyles(to: content)
        materializeListMarkers(in: content)

        let textRect = CGRect(
            x: pageMargin, y: pageMargin,
            width: pageSize.width - pageMargin * 2,
            height: pageSize.height - pageMargin * 2
        )

        // Replace image attachment runs with export-rendered attachments: the
        // decoded image scaled to the text width, centered, with the caption
        // (and "Figure N — " prefix for numbered figures) drawn beneath.
        materializeImages(in: content, textWidth: textRect.width, bodySize: DocxExporter.exportBodyPointSize)

        // TextKit 1 pagination: one text container per page.
        let storage = NSTextStorage(attributedString: content)
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)

        var containers: [NSTextContainer] = []
        repeat {
            let container = NSTextContainer(size: textRect.size)
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)
            containers.append(container)
            layoutManager.ensureLayout(for: container)
        } while NSMaxRange(layoutManager.glyphRange(for: containers[containers.count - 1]))
            < layoutManager.numberOfGlyphs

        return render(layoutManager: layoutManager, containers: containers, textRect: textRect)
    }

    /// TextKit 1 doesn't draw `NSTextList` markers, so bullets and numbers
    /// become literal prefix text in the export copy.
    private func materializeListMarkers(in content: NSMutableAttributedString) {
        let text = content.string as NSString

        var paragraphs: [NSRange] = []
        var location = 0
        while location < text.length {
            let paragraph = text.paragraphRange(for: NSRange(location: location, length: 0))
            paragraphs.append(paragraph)
            location = NSMaxRange(paragraph)
            if paragraph.length == 0 { break }
        }

        // Precompute item numbers, then insert back-to-front so ranges stay valid.
        var numbers: [Int] = []
        var current = 0
        for paragraph in paragraphs {
            if content.blockStyle(at: paragraph.location) == .numbered {
                current += 1
            } else {
                current = 0
            }
            numbers.append(current)
        }

        for (index, paragraph) in paragraphs.enumerated().reversed() {
            let blockStyle = content.blockStyle(at: paragraph.location)
            guard blockStyle.isList, paragraph.length > 0 else { continue }

            var attributes = content.attributes(at: paragraph.location, effectiveRange: nil)

            let listStyle = NSMutableParagraphStyle()
            if let existing = attributes[.paragraphStyle] as? NSParagraphStyle {
                listStyle.setParagraphStyle(existing)
            }
            listStyle.textLists = []
            listStyle.firstLineHeadIndent = 8
            listStyle.headIndent = 28
            listStyle.tabStops = [NSTextTab(textAlignment: .left, location: 28)]
            content.addAttribute(.paragraphStyle, value: listStyle, range: paragraph)

            let marker = blockStyle == .bullet ? "\u{2022}\t" : "\(numbers[index]).\t"
            attributes[.paragraphStyle] = listStyle
            content.insert(
                NSAttributedString(string: marker, attributes: attributes),
                at: paragraph.location
            )
        }
    }

    // MARK: - Image attachments

    /// Replace each `.writeImage` run's attachment with an export-rendered
    /// `NSTextAttachment` whose image is the decoded asset scaled to the text
    /// width plus the caption (with figure numbering) drawn beneath. Numbered
    /// figures count in document order — numbering is export-only.
    private func materializeImages(
        in content: NSMutableAttributedString, textWidth: CGFloat, bodySize: CGFloat
    ) {
        let full = NSRange(location: 0, length: content.length)
        var runs: [(range: NSRange, ref: ImageRef)] = []
        content.enumerateAttribute(.writeImage, in: full, options: []) { value, range, _ in
            guard let json = value as? String, let ref = json.decodedImageRef() else { return }
            runs.append((range, ref))
        }
        guard !runs.isEmpty else { return }

        // Figure numbers in document order (front-to-back).
        var figureNumber = 0
        var captions: [String] = []
        for run in runs {
            if run.ref.isFigure {
                figureNumber += 1
                let trimmed = run.ref.caption.isEmpty
                    ? "Figure \(figureNumber)"
                    : "Figure \(figureNumber) — \(run.ref.caption)"
                captions.append(trimmed)
            } else {
                captions.append(run.ref.caption)
            }
        }

        // Replace back-to-front so earlier ranges stay valid.
        for (index, run) in runs.enumerated().reversed() {
            guard let data = assets[run.ref.filename],
                  let rendered = renderImageAttachment(
                    data: data, caption: captions[index],
                    textWidth: textWidth, bodySize: bodySize
                  ) else { continue }
            var attrs = content.attributes(at: run.range.location, effectiveRange: nil)
            attrs[.attachment] = rendered
            // Center the image paragraph.
            let paragraph = NSMutableParagraphStyle()
            if let existing = attrs[.paragraphStyle] as? NSParagraphStyle {
                paragraph.setParagraphStyle(existing)
            }
            paragraph.alignment = .center
            attrs[.paragraphStyle] = paragraph
            content.replaceCharacters(
                in: run.range,
                with: NSAttributedString(string: "\u{FFFC}", attributes: attrs)
            )
        }
    }

    /// Build a plain `NSTextAttachment` whose `image` is the decoded asset
    /// scaled to `textWidth` (never upscaled) with the caption drawn beneath,
    /// and whose bounds match the rendered size so TextKit 1 lays it out.
    private func renderImageAttachment(
        data: Data, caption: String, textWidth: CGFloat, bodySize: CGFloat
    ) -> NSTextAttachment? {
        guard let source = NativeImage(data: data) else { return nil }
        let pixelSize = imagePixelSize(source)
        guard pixelSize.width > 0, pixelSize.height > 0 else { return nil }

        let scale = min(1, textWidth / pixelSize.width)
        let drawSize = CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)

        let captionFont = fontForExport(size: bodySize * 0.85)
        let captionGap: CGFloat = 6
        var captionHeight: CGFloat = 0
        let captionParagraph = NSMutableParagraphStyle()
        captionParagraph.alignment = .center
        if !caption.isEmpty {
            let bounding = (caption as NSString).boundingRect(
                with: CGSize(width: drawSize.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: captionFont, .paragraphStyle: captionParagraph],
                context: nil
            )
            captionHeight = ceil(bounding.height) + captionGap
        }

        let totalSize = CGSize(
            width: max(drawSize.width, 1),
            height: max(drawSize.height + captionHeight, 1)
        )

        let captionColor: NativeColor
        #if os(macOS)
        captionColor = NativeColor.darkGray
        #else
        captionColor = NativeColor.darkGray
        #endif
        let captionAttrs: [NSAttributedString.Key: Any] = [
            .font: captionFont,
            .foregroundColor: captionColor,
            .paragraphStyle: captionParagraph,
        ]

        #if os(macOS)
        let composite = NSImage(size: totalSize)
        composite.lockFocus()
        source.draw(
            in: NSRect(x: 0, y: captionHeight, width: drawSize.width, height: drawSize.height),
            from: .zero, operation: .sourceOver, fraction: 1
        )
        if captionHeight > 0 {
            (caption as NSString).draw(
                with: NSRect(x: 0, y: 0, width: totalSize.width, height: captionHeight - captionGap),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: captionAttrs, context: nil
            )
        }
        composite.unlockFocus()
        #else
        let renderer = UIGraphicsImageRenderer(size: totalSize)
        let composite = renderer.image { _ in
            source.draw(in: CGRect(x: 0, y: 0, width: drawSize.width, height: drawSize.height))
            if captionHeight > 0 {
                (caption as NSString).draw(
                    with: CGRect(
                        x: 0, y: drawSize.height + captionGap,
                        width: totalSize.width, height: captionHeight - captionGap
                    ),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: captionAttrs, context: nil
                )
            }
        }
        #endif

        let attachment = NSTextAttachment()
        attachment.image = composite
        attachment.bounds = CGRect(origin: .zero, size: totalSize)
        return attachment
    }

    private func imagePixelSize(_ image: NativeImage) -> CGSize {
        #if os(macOS)
        if let rep = image.representations.max(by: { $0.pixelsWide < $1.pixelsWide }),
           rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return image.size
        #else
        return CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        #endif
    }

    private func fontForExport(size: CGFloat) -> NativeFont {
        #if os(macOS)
        return NSFont.systemFont(ofSize: size)
        #else
        return UIFont.systemFont(ofSize: size)
        #endif
    }

    // MARK: - Platform rendering

    private func render(
        layoutManager: NSLayoutManager,
        containers: [NSTextContainer],
        textRect: CGRect
    ) -> Data? {
        #if os(macOS)
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { return nil }

        let previousContext = NSGraphicsContext.current
        for container in containers {
            context.beginPDFPage(nil)
            context.saveGState()
            context.translateBy(x: 0, y: pageSize.height)
            context.scaleBy(x: 1, y: -1)
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)

            let glyphRange = layoutManager.glyphRange(for: container)
            layoutManager.drawBackground(forGlyphRange: glyphRange, at: textRect.origin)
            layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: textRect.origin)

            context.restoreGState()
            context.endPDFPage()
        }
        NSGraphicsContext.current = previousContext
        context.closePDF()
        return data as Data
        #else
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        return renderer.pdfData { rendererContext in
            for container in containers {
                rendererContext.beginPage()
                let glyphRange = layoutManager.glyphRange(for: container)
                layoutManager.drawBackground(forGlyphRange: glyphRange, at: textRect.origin)
                layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: textRect.origin)
            }
        }
        #endif
    }
}
