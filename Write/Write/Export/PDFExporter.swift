#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Renders the editor's semantic attributed string into a paginated PDF
/// using the document's configured styles.
struct PDFExporter {
    let configuration: StyleConfiguration

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
        var styler = RichTextStyler(configuration: configuration, zoomScale: 1.0)
        styler.forExport = true
        styler.applyStyles(to: content)
        materializeListMarkers(in: content)

        let textRect = CGRect(
            x: pageMargin, y: pageMargin,
            width: pageSize.width - pageMargin * 2,
            height: pageSize.height - pageMargin * 2
        )

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
