import Foundation

/// Exports the editor's semantic attributed string as a Word document.
/// Headings map to native Word heading styles so the document outline,
/// navigation pane, and table-of-contents features work.
///
/// When a `ReferenceExportContext` is supplied:
///   • Cited items are emitted as `b:Source` nodes in a `customXml/item1.xml`
///     part that Word's Manage Sources dialog reads natively.
///   • `.writeCitation` chip runs become `w:sdt` blocks containing a
///     CITATION complex field.
///   • The bibliography region becomes a single `w:sdt` block containing a
///     BIBLIOGRAPHY complex field; URLs inside entries become real hyperlinks.
struct DocxExporter {
    let configuration: StyleConfiguration
    /// Optional reference context; when nil the export is identical to the
    /// pre-P3 behaviour (no customXml, no sdt).
    let references: ReferenceExportContext?
    /// Image assets keyed by filename, embedded as `word/media/*` parts.
    let assets: [String: Data]

    init(
        configuration: StyleConfiguration,
        references: ReferenceExportContext? = nil,
        assets: [String: Data] = [:]
    ) {
        self.configuration = configuration
        self.references = references
        self.assets = assets
    }

    /// Exports normalize the body size to standard print sizing, scaling
    /// every other style proportionally.
    static let exportBodyPointSize: CGFloat = 11

    private var exportScale: CGFloat {
        Self.exportBodyPointSize / max(configuration.paragraph.fontSize, 1)
    }

    private static let bulletNumId = 1
    /// Numbered runs allocate fresh numbering instances starting here so
    /// each list restarts at 1.
    private static let firstDecimalNumId = 2

    // MARK: - Media plan

    /// One embedded image: its media filename, relationship id, content-type
    /// extension, the (possibly transcoded) bytes, display extent in EMUs, and
    /// the figure number when it's a numbered figure (0 otherwise).
    private struct MediaImage {
        let location: Int              // character location of the image run
        let mediaFilename: String      // e.g. "image1.png"
        let relationshipID: String     // e.g. "rId5"
        let ext: String                // lowercased, e.g. "png"
        let bytes: Data
        let widthEMU: Int
        let heightEMU: Int
        let caption: String
        let figureNumber: Int          // 0 = not a numbered figure
        let docPrID: Int
    }

    func docxData(from attributed: NSAttributedString) -> Data {
        // Collect all cited item IDs so we know which sources to include.
        let (citedIDs, hasBibliographyRegion) = collectCitedInfo(from: attributed)

        // Build tag registry and determine which CSLItems to export.
        var tagRegistry = WordTagRegistry()
        var citedItems: [CSLItem] = []
        var tagByID: [String: String] = [:]

        if let refs = references, !citedIDs.isEmpty || hasBibliographyRegion {
            // Include all items present in the store when a bibliography region
            // exists (so Word can render the full list on refresh), otherwise
            // only cited items.
            let itemsToExport = hasBibliographyRegion
                ? refs.items
                : refs.items.filter { citedIDs.contains($0.id) }
            citedItems = itemsToExport
            for item in itemsToExport {
                tagByID[item.id] = tagRegistry.tag(for: item.id)
            }
        }

        let needsCustomXml = !citedItems.isEmpty

        // Accumulate external hyperlink relationships.
        // rId1=styles, rId2=numbering, rId3=customXml (if present), then image
        // relationships, then rId…=hyperlinks.
        var hyperlinkRels: [(id: String, url: String)] = []
        var hyperlinkRelsByURL: [String: String] = [:]
        var nextRelIndex = needsCustomXml ? 4 : 3

        // Image pre-pass: assign media filenames, relationship ids, content
        // types, figure numbers, and EMU extents (transcoding HEIC → PNG).
        let mediaImages = planMedia(from: attributed, nextRelIndex: &nextRelIndex)
        let mediaByRunIndex: [Int: MediaImage] = Dictionary(
            uniqueKeysWithValues: mediaImages.map { ($0.location, $0) }
        )

        // SDT id counter — negative to avoid collision with any Word-assigned ids.
        // -1 is reserved for the bibliography SDT; citations start at -2 downward.
        var sdtIDCounter = -2

        let (body, decimalListCount) = documentBody(
            from: attributed,
            tagByID: tagByID,
            mediaByRunIndex: mediaByRunIndex,
            hyperlinkRels: &hyperlinkRels,
            hyperlinkRelsByURL: &hyperlinkRelsByURL,
            nextHyperlinkIndex: &nextRelIndex,
            sdtIDCounter: &sdtIDCounter
        )

        let hasImages = !mediaImages.isEmpty

        var archive = ZipArchive()
        archive.addFile(named: "[Content_Types].xml",
                        data: Data(contentTypesXML(
                            needsCustomXml: needsCustomXml,
                            imageExtensions: Set(mediaImages.map(\.ext))
                        ).utf8))
        archive.addFile(named: "_rels/.rels", data: Data(relsXML.utf8))
        archive.addFile(named: "word/_rels/document.xml.rels",
                        data: Data(documentRelsXML(
                            needsCustomXml: needsCustomXml,
                            hyperlinkRels: hyperlinkRels,
                            mediaImages: mediaImages
                        ).utf8))
        archive.addFile(named: "word/document.xml", data: Data(documentXML(body: body).utf8))
        archive.addFile(named: "word/styles.xml", data: Data(stylesXML(includeCaption: hasImages).utf8))
        archive.addFile(
            named: "word/numbering.xml",
            data: Data(numberingXML(decimalListCount: decimalListCount).utf8)
        )

        // Embed image media parts, byte-identical to the (possibly transcoded)
        // input. Originals are never modified in the package.
        for image in mediaImages {
            archive.addFile(named: "word/media/\(image.mediaFilename)", data: image.bytes)
        }

        if needsCustomXml {
            let pkg = buildBibliographyPackage(
                citing: citedItems,
                tagRegistry: &tagRegistry,
                escaping: escapeXML
            )
            archive.addFile(named: "customXml/item1.xml", data: Data(pkg.item1XML.utf8))
            archive.addFile(named: "customXml/itemProps1.xml", data: Data(pkg.itemProps1XML.utf8))
            archive.addFile(named: "customXml/_rels/item1.xml.rels", data: Data(pkg.itemRelsXML.utf8))
        }

        return archive.archiveData()
    }

    // MARK: - Citation / bibliography pre-pass

    private func collectCitedInfo(from attributed: NSAttributedString) -> (citedIDs: Set<String>, hasBibliographyRegion: Bool) {
        var citedIDs = Set<String>()
        var hasBibliographyRegion = false
        let fullRange = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttributes(in: fullRange, options: []) { attrs, _, _ in
            if let json = attrs[.writeCitation] as? String,
               let refs = json.decodedCitationRefs() {
                for ref in refs { citedIDs.insert(ref.itemID) }
            }
            if let flag = attrs[.writeBibliography] as? NSNumber, flag.boolValue {
                hasBibliographyRegion = true
            }
        }
        return (citedIDs, hasBibliographyRegion)
    }

    // MARK: - Media pre-pass

    /// EMUs per inch (English Metric Units; the DrawingML measurement).
    private static let emuPerInch = 914_400
    /// Page text width in EMUs: 8.5in page − 1in margins each side = 6.5in.
    private static let textWidthEMU = Int(6.5 * 914_400)

    /// Walk every `.writeImage` run, decode each asset to size it, transcode
    /// HEIC → PNG (originals stay untouched in the document package), assign a
    /// media filename + relationship id + content-type extension, compute its
    /// EMU extent scaled to the text width (preserving aspect), and number
    /// figures in document order.
    private func planMedia(
        from attributed: NSAttributedString, nextRelIndex: inout Int
    ) -> [MediaImage] {
        let full = NSRange(location: 0, length: attributed.length)
        var runs: [(location: Int, ref: ImageRef)] = []
        attributed.enumerateAttribute(.writeImage, in: full, options: []) { value, range, _ in
            guard let json = value as? String, let ref = json.decodedImageRef() else { return }
            runs.append((range.location, ref))
        }
        guard !runs.isEmpty else { return [] }

        var result: [MediaImage] = []
        var imageCounter = 0
        var figureCounter = 0
        var docPrCounter = 1

        for run in runs {
            guard let originalData = assets[run.ref.filename] else { continue }
            let originalExt = (run.ref.filename as NSString).pathExtension.lowercased()

            // Decode for sizing; transcode HEIC/HEIF → PNG (Word can't read HEIC).
            guard let decoded = DocxImageCodec.prepare(
                data: originalData, ext: originalExt
            ) else { continue }

            imageCounter += 1
            let mediaFilename = "image\(imageCounter).\(decoded.ext)"
            let relationshipID = "rId\(nextRelIndex)"
            nextRelIndex += 1

            let (widthEMU, heightEMU) = emuExtent(
                pixelWidth: decoded.pixelWidth, pixelHeight: decoded.pixelHeight
            )

            var figureNumber = 0
            if run.ref.isFigure {
                figureCounter += 1
                figureNumber = figureCounter
            }

            result.append(MediaImage(
                location: run.location,
                mediaFilename: mediaFilename,
                relationshipID: relationshipID,
                ext: decoded.ext,
                bytes: decoded.bytes,
                widthEMU: widthEMU,
                heightEMU: heightEMU,
                caption: run.ref.caption,
                figureNumber: figureNumber,
                docPrID: docPrCounter
            ))
            docPrCounter += 1
        }
        return result
    }

    /// Display extent in EMUs scaled to fit the text width (never upscaling),
    /// preserving aspect ratio.
    private func emuExtent(pixelWidth: Int, pixelHeight: Int) -> (width: Int, height: Int) {
        guard pixelWidth > 0, pixelHeight > 0 else {
            return (Self.textWidthEMU, Self.textWidthEMU)
        }
        // Assume 96 dpi for the source so EMUs map sensibly, then clamp width.
        let dpi = 96.0
        let naturalWidthEMU = Double(pixelWidth) / dpi * Double(Self.emuPerInch)
        let widthEMU = min(naturalWidthEMU, Double(Self.textWidthEMU))
        let heightEMU = widthEMU * Double(pixelHeight) / Double(pixelWidth)
        return (Int(widthEMU.rounded()), Int(heightEMU.rounded()))
    }

    // MARK: - Body

    private func documentBody(
        from attributed: NSAttributedString,
        tagByID: [String: String],
        mediaByRunIndex: [Int: MediaImage],
        hyperlinkRels: inout [(id: String, url: String)],
        hyperlinkRelsByURL: inout [String: String],
        nextHyperlinkIndex: inout Int,
        sdtIDCounter: inout Int
    ) -> (xml: String, decimalListCount: Int) {
        let text = attributed.string as NSString
        var xml = ""
        var decimalListCount = 0
        var previousStyle: BlockStyle?

        // State machine for the bibliography SDT wrapper.
        // The heading paragraph of the bibliography region is emitted normally;
        // all subsequent bibliography paragraphs are collected, wrapped with a
        // BIBLIOGRAPHY complex field, and flushed as a single SDT block when the
        // region ends (either at a non-bibliography paragraph or end of document).
        var bibliographyHeadingSeen = false
        // Accumulate entry paragraph XML fragments until the region closes.
        var pendingEntries: [String] = []

        /// Flush accumulated bibliography entries as a BIBLIOGRAPHY SDT block.
        /// The BIBLIOGRAPHY complex field spans the first and last paragraphs:
        ///   first paragraph: begin fldChar + instrText + separate fldChar + content
        ///   inner paragraphs: content only
        ///   last paragraph: content + end fldChar
        func flushBibliographySDT() {
            guard !pendingEntries.isEmpty else { return }
            // Inject field runs into the first and last entry paragraphs.
            // Each entry is a full `<w:p>…</w:p>` string; we insert runs
            // at the opening and closing of the first/last paragraph elements.
            let fieldBegin = "<w:r><w:fldChar w:fldCharType=\"begin\"/></w:r>"
                + "<w:r><w:instrText xml:space=\"preserve\"> BIBLIOGRAPHY </w:instrText></w:r>"
                + "<w:r><w:fldChar w:fldCharType=\"separate\"/></w:r>"
            let fieldEnd = "<w:r><w:fldChar w:fldCharType=\"end\"/></w:r>"

            var entries = pendingEntries
            // Insert begin runs after the opening <w:p> (or <w:p>) of first entry.
            let firstTag = "<w:p>"
            if let range = entries[0].range(of: firstTag) {
                let insertAt = range.upperBound
                entries[0].insert(contentsOf: fieldBegin, at: insertAt)
            }
            // Insert end run before the closing </w:p> of last entry.
            let lastTag = "</w:p>"
            if let range = entries[entries.count - 1].range(of: lastTag, options: .backwards) {
                entries[entries.count - 1].insert(contentsOf: fieldEnd, at: range.lowerBound)
            }

            xml += "<w:sdt>"
            xml += "<w:sdtPr><w:id w:val=\"-1\"/><w:bibliography/></w:sdtPr>"
            xml += "<w:sdtContent>"
            for entry in entries { xml += entry }
            xml += "</w:sdtContent></w:sdt>"
            pendingEntries = []
        }

        var location = 0
        while location < text.length {
            let paragraph = text.paragraphRange(for: NSRange(location: location, length: 0))
            var contentLength = paragraph.length
            if contentLength > 0, text.character(at: NSMaxRange(paragraph) - 1) == 0x0A {
                contentLength -= 1
            }
            let contentRange = NSRange(location: paragraph.location, length: contentLength)
            let blockStyle = attributed.blockStyle(at: paragraph.location)

            // Check whether this paragraph is part of the bibliography region.
            let isBiblioPara = paragraph.location < attributed.length &&
                (attributed.attribute(.writeBibliography, at: paragraph.location, effectiveRange: nil) as? NSNumber)?.boolValue == true

            if blockStyle == .numbered, previousStyle != .numbered {
                decimalListCount += 1
            }

            if isBiblioPara && references != nil {
                if !bibliographyHeadingSeen {
                    // First bibliography paragraph = heading; flush any stale
                    // accumulated entries first (shouldn't happen but guard).
                    flushBibliographySDT()
                    bibliographyHeadingSeen = true
                    xml += paragraphXML(
                        blockStyle: blockStyle,
                        contentRange: contentRange,
                        in: attributed,
                        decimalNumId: Self.firstDecimalNumId + decimalListCount - 1,
                        tagByID: tagByID,
                        hyperlinkRels: &hyperlinkRels,
                        hyperlinkRelsByURL: &hyperlinkRelsByURL,
                        nextHyperlinkIndex: &nextHyperlinkIndex,
                        sdtIDCounter: &sdtIDCounter
                    )
                } else {
                    // Accumulate entry paragraph XML.
                    pendingEntries.append(bibliographyEntryParagraphXML(
                        blockStyle: blockStyle,
                        contentRange: contentRange,
                        in: attributed,
                        hyperlinkRels: &hyperlinkRels,
                        hyperlinkRelsByURL: &hyperlinkRelsByURL,
                        nextHyperlinkIndex: &nextHyperlinkIndex
                    ))
                }
            } else if contentRange.length == 1,
                      let media = mediaByRunIndex[contentRange.location],
                      attributed.attribute(.writeImage, at: contentRange.location, effectiveRange: nil) is String {
                // Image paragraph: an inline drawing, plus a Caption paragraph
                // (with a SEQ Figure field) when it's a numbered figure.
                flushBibliographySDT()
                xml += imageParagraphXML(media)
                if media.figureNumber > 0 {
                    xml += captionParagraphXML(media)
                }
            } else {
                // Non-bibliography paragraph: flush any accumulated entries first.
                flushBibliographySDT()
                xml += paragraphXML(
                    blockStyle: blockStyle,
                    contentRange: contentRange,
                    in: attributed,
                    decimalNumId: Self.firstDecimalNumId + decimalListCount - 1,
                    tagByID: tagByID,
                    hyperlinkRels: &hyperlinkRels,
                    hyperlinkRelsByURL: &hyperlinkRelsByURL,
                    nextHyperlinkIndex: &nextHyperlinkIndex,
                    sdtIDCounter: &sdtIDCounter
                )
            }

            previousStyle = blockStyle
            location = NSMaxRange(paragraph)
            if paragraph.length == 0 { break }
        }

        // Flush any remaining bibliography entries at end of document.
        flushBibliographySDT()

        if xml.isEmpty {
            xml = "<w:p/>"
        }
        return (xml, decimalListCount)
    }

    // MARK: - Paragraph XML

    private func paragraphXML(
        blockStyle: BlockStyle,
        contentRange: NSRange,
        in attributed: NSAttributedString,
        decimalNumId: Int,
        tagByID: [String: String],
        hyperlinkRels: inout [(id: String, url: String)],
        hyperlinkRelsByURL: inout [String: String],
        nextHyperlinkIndex: inout Int,
        sdtIDCounter: inout Int
    ) -> String {
        var properties = ""
        switch blockStyle {
        case .body:
            break
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6:
            properties += "<w:pStyle w:val=\"Heading\(blockStyle.headingLevel ?? 1)\"/>"
        case .quote:
            properties += "<w:pStyle w:val=\"Quote\"/>"
        case .code:
            properties += "<w:pStyle w:val=\"CodeBlock\"/>"
        case .bullet:
            properties += "<w:pStyle w:val=\"ListParagraph\"/>"
            properties += "<w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"\(Self.bulletNumId)\"/></w:numPr>"
        case .numbered:
            properties += "<w:pStyle w:val=\"ListParagraph\"/>"
            properties += "<w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"\(decimalNumId)\"/></w:numPr>"
        }

        var runs = ""
        if contentRange.length > 0 {
            attributed.enumerateAttributes(in: contentRange, options: []) { attrs, runRange, _ in
                if let json = attrs[.writeCitation] as? String,
                   let refs = json.decodedCitationRefs(),
                   !refs.isEmpty,
                   references != nil {
                    // Citation chip → CITATION field SDT.
                    let displayText = (attributed.string as NSString).substring(with: runRange)
                    runs += citationSDTXML(
                        refs: refs,
                        tagByID: tagByID,
                        displayText: displayText,
                        sdtIDCounter: &sdtIDCounter
                    )
                } else {
                    let runText = (attributed.string as NSString).substring(with: runRange)
                    runs += runXML(text: runText, traits: attrs.inlineTraits)
                }
            }
        }

        let propertiesXML = properties.isEmpty ? "" : "<w:pPr>\(properties)</w:pPr>"
        return "<w:p>\(propertiesXML)\(runs)</w:p>"
    }

    // MARK: - Image paragraphs

    /// An image paragraph: a centered paragraph containing a single inline
    /// `w:drawing` whose blip references the media relationship, sized to the
    /// computed EMU extent.
    private func imageParagraphXML(_ media: MediaImage) -> String {
        let docPrName = "Image \(media.docPrID)"
        let drawing = """
        <w:drawing>\
        <wp:inline distT="0" distB="0" distL="0" distR="0">\
        <wp:extent cx="\(media.widthEMU)" cy="\(media.heightEMU)"/>\
        <wp:effectExtent l="0" t="0" r="0" b="0"/>\
        <wp:docPr id="\(media.docPrID)" name="\(escapeXML(docPrName))"/>\
        <wp:cNvGraphicFramePr>\
        <a:graphicFrameLocks xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" noChangeAspect="1"/>\
        </wp:cNvGraphicFramePr>\
        <a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">\
        <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">\
        <pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">\
        <pic:nvPicPr>\
        <pic:cNvPr id="\(media.docPrID)" name="\(escapeXML(media.mediaFilename))"/>\
        <pic:cNvPicPr/>\
        </pic:nvPicPr>\
        <pic:blipFill>\
        <a:blip r:embed="\(media.relationshipID)"/>\
        <a:stretch><a:fillRect/></a:stretch>\
        </pic:blipFill>\
        <pic:spPr>\
        <a:xfrm><a:off x="0" y="0"/><a:ext cx="\(media.widthEMU)" cy="\(media.heightEMU)"/></a:xfrm>\
        <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>\
        </pic:spPr>\
        </pic:pic>\
        </a:graphicData>\
        </a:graphic>\
        </wp:inline>\
        </w:drawing>
        """
        return "<w:p><w:pPr><w:jc w:val=\"center\"/></w:pPr><w:r>\(drawing)</w:r></w:p>"
    }

    /// A Caption-styled paragraph for a numbered figure:
    /// "Figure " + SEQ Figure field (numeric result) + " — " + caption.
    private func captionParagraphXML(_ media: MediaImage) -> String {
        let seqField = "<w:r><w:fldChar w:fldCharType=\"begin\"/></w:r>"
            + "<w:r><w:instrText xml:space=\"preserve\"> SEQ Figure \\* ARABIC </w:instrText></w:r>"
            + "<w:r><w:fldChar w:fldCharType=\"separate\"/></w:r>"
            + "<w:r><w:t>\(media.figureNumber)</w:t></w:r>"
            + "<w:r><w:fldChar w:fldCharType=\"end\"/></w:r>"

        let label = "<w:r><w:t xml:space=\"preserve\">Figure </w:t></w:r>"
        let caption = media.caption.isEmpty
            ? ""
            : "<w:r><w:t xml:space=\"preserve\"> — \(escapeXML(media.caption))</w:t></w:r>"

        return "<w:p><w:pPr><w:pStyle w:val=\"Caption\"/></w:pPr>"
            + label + seqField + caption
            + "</w:p>"
    }

    // MARK: - Citation SDT

    /// Returns a `w:sdt` CITATION field block for a citation chip.
    ///
    /// **Multi-ref limitation**: Word's CITATION field accepts exactly one tag.
    /// When a chip references multiple sources only the first is wired as the
    /// CITATION field; remaining refs' display text is folded into the field
    /// result as plain text only. Word's "Update Field" will lose the extra
    /// refs. This limitation is documented in the export report.
    private func citationSDTXML(
        refs: [CitationRef],
        tagByID: [String: String],
        displayText: String,
        sdtIDCounter: inout Int
    ) -> String {
        let id = sdtIDCounter
        sdtIDCounter -= 1

        let firstRef = refs[0]
        let tag = tagByID[firstRef.itemID] ?? escapeXML(firstRef.itemID)

        // Build CITATION field instrText.
        var instr = " CITATION \(tag)"
        // Add \p locator when the first ref has a page-type locator.
        if let locator = firstRef.locator, !locator.isEmpty {
            let label = firstRef.label ?? "page"
            if label == "page" || label == "pages" {
                instr += " \\p \(locator)"
            }
        }
        instr += " \\l 1033 "

        // Field result = chip's current display text as a plain run.
        let resultRun = "<w:r><w:t xml:space=\"preserve\">\(escapeXML(displayText))</w:t></w:r>"

        return "<w:sdt>"
            + "<w:sdtPr><w:id w:val=\"\(id)\"/><w:citation/></w:sdtPr>"
            + "<w:sdtContent>"
            + "<w:p>"
            + "<w:r><w:fldChar w:fldCharType=\"begin\"/></w:r>"
            + "<w:r><w:instrText xml:space=\"preserve\">\(escapeXML(instr))</w:instrText></w:r>"
            + "<w:r><w:fldChar w:fldCharType=\"separate\"/></w:r>"
            + resultRun
            + "<w:r><w:fldChar w:fldCharType=\"end\"/></w:r>"
            + "</w:p>"
            + "</w:sdtContent>"
            + "</w:sdt>"
    }

    // MARK: - Bibliography entry paragraph

    /// Emits a bibliography entry paragraph, post-processing any http(s) URL
    /// spans into real `w:hyperlink` elements.
    private func bibliographyEntryParagraphXML(
        blockStyle: BlockStyle,
        contentRange: NSRange,
        in attributed: NSAttributedString,
        hyperlinkRels: inout [(id: String, url: String)],
        hyperlinkRelsByURL: inout [String: String],
        nextHyperlinkIndex: inout Int
    ) -> String {
        // Collect (text, traits) segments for this paragraph.
        struct RunSeg { let text: String; let traits: InlineTraits }
        var segs: [RunSeg] = []
        if contentRange.length > 0 {
            attributed.enumerateAttributes(in: contentRange, options: []) { attrs, runRange, _ in
                let t = (attributed.string as NSString).substring(with: runRange)
                segs.append(RunSeg(text: t, traits: attrs.inlineTraits))
            }
        }

        // Reconstruct the full paragraph text and find URL spans.
        let fullText = segs.map(\.text).joined()
        let urlSpans = findHyperlinkSpans(in: fullText)

        guard !urlSpans.isEmpty else {
            // Fast path: no hyperlinks, emit normally.
            var runs = ""
            for seg in segs { runs += runXML(text: seg.text, traits: seg.traits) }
            return "<w:p>\(runs)</w:p>"
        }

        // Build a segment offset table for trait lookup.
        var segStarts: [Int] = []
        var off = 0
        for seg in segs {
            segStarts.append(off)
            off += (seg.text as NSString).length
        }

        /// Returns InlineTraits dominant at a given UTF-16 offset into fullText.
        func traits(at offset: Int) -> InlineTraits {
            for (i, start) in segStarts.enumerated() {
                let end = start + (segs[i].text as NSString).length
                if offset < end { return segs[i].traits }
            }
            return []
        }

        // Merge text and hyperlink chunks in order.
        let nsFullText = fullText as NSString
        let totalLen = nsFullText.length
        struct Chunk { let range: NSRange; let url: String? }
        var chunks: [Chunk] = []
        var cursor = 0
        for span in urlSpans.sorted(by: { $0.range.location < $1.range.location }) {
            if span.range.location > cursor {
                chunks.append(Chunk(range: NSRange(location: cursor, length: span.range.location - cursor), url: nil))
            }
            chunks.append(Chunk(range: span.range, url: span.url))
            cursor = NSMaxRange(span.range)
        }
        if cursor < totalLen {
            chunks.append(Chunk(range: NSRange(location: cursor, length: totalLen - cursor), url: nil))
        }

        var runs = ""
        for chunk in chunks {
            let chunkText = nsFullText.substring(with: chunk.range)
            let chunkTraits = traits(at: chunk.range.location)

            if let url = chunk.url {
                // Register the hyperlink relationship (deduplicate by URL).
                let rId: String
                if let existing = hyperlinkRelsByURL[url] {
                    rId = existing
                } else {
                    rId = "rId\(nextHyperlinkIndex)"
                    nextHyperlinkIndex += 1
                    hyperlinkRels.append((id: rId, url: url))
                    hyperlinkRelsByURL[url] = rId
                }
                // Hyperlink runs always emit blue + underline styling;
                // other traits from chunkTraits are intentionally dropped
                // to keep the hyperlink appearance consistent.
                let linkRun = "<w:r>"
                    + "<w:rPr><w:u w:val=\"single\"/><w:color w:val=\"0563C1\"/></w:rPr>"
                    + "<w:t xml:space=\"preserve\">\(escapeXML(chunkText))</w:t>"
                    + "</w:r>"
                runs += "<w:hyperlink r:id=\"\(rId)\">\(linkRun)</w:hyperlink>"
            } else {
                runs += runXML(text: chunkText, traits: chunkTraits)
            }
        }

        return "<w:p>\(runs)</w:p>"
    }

    // MARK: - Run builder

    private func runXML(text: String, traits: InlineTraits) -> String {
        var properties = ""
        if traits.contains(.code) {
            let mono = escapeXML(monoFontName)
            properties += "<w:rFonts w:ascii=\"\(mono)\" w:hAnsi=\"\(mono)\" w:cs=\"\(mono)\"/>"
        }
        if traits.contains(.bold) { properties += "<w:b/>" }
        if traits.contains(.italic) { properties += "<w:i/>" }
        if traits.contains(.strikethrough) { properties += "<w:strike/>" }
        if traits.contains(.underline) { properties += "<w:u w:val=\"single\"/>" }
        if traits.contains(.superscript) { properties += "<w:vertAlign w:val=\"superscript\"/>" }
        if traits.contains(.subscriptText) { properties += "<w:vertAlign w:val=\"subscript\"/>" }
        let propertiesXML = properties.isEmpty ? "" : "<w:rPr>\(properties)</w:rPr>"

        // Hard line breaks within a paragraph become <w:br/>.
        let segments = text.components(separatedBy: "\u{2028}")
        let content = segments
            .map { "<w:t xml:space=\"preserve\">\(escapeXML($0))</w:t>" }
            .joined(separator: "<w:br/>")

        return "<w:r>\(propertiesXML)\(content)</w:r>"
    }

    // MARK: - Package parts

    private func contentTypesXML(needsCustomXml: Bool, imageExtensions: Set<String>) -> String {
        var overrides = """
        <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
        <Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>
        """
        if needsCustomXml {
            overrides += "\n<Override PartName=\"/customXml/item1.xml\" ContentType=\"application/xml\"/>"
            overrides += "\n<Override PartName=\"/customXml/itemProps1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.customXmlProperties+xml\"/>"
        }

        // Default content types per image extension present in the package.
        let mimeByExt: [String: String] = [
            "png": "image/png",
            "jpeg": "image/jpeg",
            "gif": "image/gif",
            "tiff": "image/tiff",
            "bmp": "image/bmp",
        ]
        var imageDefaults = ""
        for ext in imageExtensions.sorted() {
            let mime = mimeByExt[ext] ?? "image/\(ext)"
            imageDefaults += "\n<Default Extension=\"\(ext)\" ContentType=\"\(mime)\"/>"
        }

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>\(imageDefaults)
        \(overrides)
        </Types>
        """
    }

    private var relsXML: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """
    }

    /// Parts are discovered through relationships, not filenames — without
    /// these entries importers silently ignore styles.xml and numbering.xml.
    private func documentRelsXML(
        needsCustomXml: Bool,
        hyperlinkRels: [(id: String, url: String)],
        mediaImages: [MediaImage]
    ) -> String {
        var rels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>
        """
        if needsCustomXml {
            rels += "\n<Relationship Id=\"rId3\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/customXml\" Target=\"../customXml/item1.xml\"/>"
        }
        for media in mediaImages {
            rels += "\n<Relationship Id=\"\(media.relationshipID)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/\(media.mediaFilename)\"/>"
        }
        for rel in hyperlinkRels {
            rels += "\n<Relationship Id=\"\(rel.id)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" Target=\"\(escapeXML(rel.url))\" TargetMode=\"External\"/>"
        }
        rels += "\n</Relationships>"
        return rels
    }

    private func documentXML(body: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
        <w:body>\(body)<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr></w:body>
        </w:document>
        """
    }

    private func stylesXML(includeCaption: Bool) -> String {
        var styles = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <w:docDefaults><w:rPrDefault><w:rPr>\(runFontsXML(for: configuration.paragraph))</w:rPr></w:rPrDefault></w:docDefaults>
        <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/>\(paragraphPropertiesXML(for: configuration.paragraph))<w:rPr>\(runFontsXML(for: configuration.paragraph))</w:rPr></w:style>
        """

        // Child order inside w:style and w:pPr follows the OOXML schema
        // (qFormat before pPr; spacing before ind/outlineLvl; shd before
        // spacing) — strict importers discard the whole styles part otherwise.
        for level in 1...6 {
            let style = configuration.styleForHeading(level: level)
            styles += """
            <w:style w:type="paragraph" w:styleId="Heading\(level)"><w:name w:val="heading \(level)"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr>\(spacingXML(for: style))<w:outlineLvl w:val="\(level - 1)"/></w:pPr><w:rPr>\(runFontsXML(for: style))\(style.fontWeight.isBoldForExport ? "<w:b/>" : "")\(style.isItalic ? "<w:i/>" : "")</w:rPr></w:style>
            """
        }

        styles += """
        <w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/><w:basedOn w:val="Normal"/><w:qFormat/><w:pPr>\(spacingXML(for: configuration.blockquote))<w:ind w:left="720"/></w:pPr><w:rPr>\(runFontsXML(for: configuration.blockquote))\(configuration.blockquote.isItalic ? "<w:i/>" : "")<w:color w:val="595959"/></w:rPr></w:style>
        <w:style w:type="paragraph" w:styleId="CodeBlock"><w:name w:val="Code Block"/><w:basedOn w:val="Normal"/><w:pPr><w:shd w:val="clear" w:color="auto" w:fill="F2F2F2"/>\(spacingXML(for: configuration.code))</w:pPr><w:rPr>\(runFontsXML(for: configuration.code))</w:rPr></w:style>
        <w:style w:type="paragraph" w:styleId="ListParagraph"><w:name w:val="List Paragraph"/><w:basedOn w:val="Normal"/><w:qFormat/><w:pPr><w:ind w:left="720"/></w:pPr></w:style>
        """

        if includeCaption {
            // Caption: basedOn Normal, 0.85× body size, italic, centered.
            // Child order: name → basedOn → next → qFormat → pPr → rPr.
            let halfPoints = Int((configuration.paragraph.fontSize * exportScale * 0.85 * 2).rounded())
            styles += """
            <w:style w:type="paragraph" w:styleId="Caption"><w:name w:val="caption"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr>\(spacingXML(for: configuration.paragraph))<w:jc w:val="center"/></w:pPr><w:rPr><w:i/><w:sz w:val="\(halfPoints)"/><w:szCs w:val="\(halfPoints)"/></w:rPr></w:style>
            """
        }

        styles += "</w:styles>"
        return styles
    }

    private func numberingXML(decimalListCount: Int) -> String {
        var numbering = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:abstractNum w:abstractNumId="0"><w:multiLevelType w:val="singleLevel"/><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="bullet"/><w:lvlText w:val="&#8226;"/><w:lvlJc w:val="left"/><w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr></w:lvl></w:abstractNum>
        <w:abstractNum w:abstractNumId="1"><w:multiLevelType w:val="singleLevel"/><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1."/><w:lvlJc w:val="left"/><w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr></w:lvl></w:abstractNum>
        <w:num w:numId="\(Self.bulletNumId)"><w:abstractNumId w:val="0"/></w:num>
        """

        for index in 0..<max(decimalListCount, 1) {
            let numId = Self.firstDecimalNumId + index
            numbering += """
            <w:num w:numId="\(numId)"><w:abstractNumId w:val="1"/><w:lvlOverride w:ilvl="0"><w:startOverride w:val="1"/></w:lvlOverride></w:num>
            """
        }

        numbering += "</w:numbering>"
        return numbering
    }

    // MARK: - Style helpers

    private func paragraphPropertiesXML(for style: ElementStyle) -> String {
        "<w:pPr>\(spacingXML(for: style))</w:pPr>"
    }

    private func spacingXML(for style: ElementStyle) -> String {
        let before = Int((style.paragraphSpacingBefore * exportScale * 20).rounded())
        let after = Int((style.paragraphSpacingAfter * exportScale * 20).rounded())
        return "<w:spacing w:before=\"\(before)\" w:after=\"\(after)\"/>"
    }

    private func runFontsXML(for style: ElementStyle) -> String {
        let family = escapeXML(exportFontName(for: style.fontFamily))
        let halfPoints = Int((style.fontSize * exportScale * 2).rounded())
        return "<w:rFonts w:ascii=\"\(family)\" w:hAnsi=\"\(family)\" w:cs=\"\(family)\"/><w:sz w:val=\"\(halfPoints)\"/><w:szCs w:val=\"\(halfPoints)\"/>"
    }

    /// San Francisco isn't available outside Apple platforms, so the system
    /// font maps to a neutral default for Word.
    private func exportFontName(for family: String) -> String {
        if family == FontResolver.systemFamilyName || family.isEmpty {
            return "Helvetica Neue"
        }
        return family
    }

    private var monoFontName: String {
        exportFontName(for: configuration.code.fontFamily) == "SF Mono"
            ? "Menlo"
            : exportFontName(for: configuration.code.fontFamily)
    }

    private func escapeXML(_ string: String) -> String {
        var result = ""
        result.reserveCapacity(string.count)
        for character in string {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&apos;"
            default: result.append(character)
            }
        }
        return result
    }
}

private extension FontWeight {
    var isBoldForExport: Bool {
        self == .semibold || self == .bold || self == .heavy || self == .black
    }
}
