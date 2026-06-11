import Foundation

/// Exports the editor's semantic attributed string as a Word document.
/// Headings map to native Word heading styles so the document outline,
/// navigation pane, and table-of-contents features work.
struct DocxExporter {
    let configuration: StyleConfiguration

    private static let bulletNumId = 1
    /// Numbered runs allocate fresh numbering instances starting here so
    /// each list restarts at 1.
    private static let firstDecimalNumId = 2

    func docxData(from attributed: NSAttributedString) -> Data {
        let (body, decimalListCount) = documentBody(from: attributed)

        var archive = ZipArchive()
        archive.addFile(named: "[Content_Types].xml", data: Data(contentTypesXML.utf8))
        archive.addFile(named: "_rels/.rels", data: Data(relsXML.utf8))
        archive.addFile(named: "word/document.xml", data: Data(documentXML(body: body).utf8))
        archive.addFile(named: "word/styles.xml", data: Data(stylesXML.utf8))
        archive.addFile(
            named: "word/numbering.xml",
            data: Data(numberingXML(decimalListCount: decimalListCount).utf8)
        )
        return archive.archiveData()
    }

    // MARK: - Body

    private func documentBody(from attributed: NSAttributedString) -> (xml: String, decimalListCount: Int) {
        let text = attributed.string as NSString
        var xml = ""
        var decimalListCount = 0
        var previousStyle: BlockStyle?

        var location = 0
        while location < text.length {
            let paragraph = text.paragraphRange(for: NSRange(location: location, length: 0))
            var contentLength = paragraph.length
            if contentLength > 0, text.character(at: NSMaxRange(paragraph) - 1) == 0x0A {
                contentLength -= 1
            }
            let contentRange = NSRange(location: paragraph.location, length: contentLength)
            let blockStyle = attributed.blockStyle(at: paragraph.location)

            if blockStyle == .numbered, previousStyle != .numbered {
                decimalListCount += 1
            }

            xml += paragraphXML(
                blockStyle: blockStyle,
                contentRange: contentRange,
                in: attributed,
                decimalNumId: Self.firstDecimalNumId + decimalListCount - 1
            )

            previousStyle = blockStyle
            location = NSMaxRange(paragraph)
            if paragraph.length == 0 { break }
        }

        if xml.isEmpty {
            xml = "<w:p/>"
        }
        return (xml, decimalListCount)
    }

    private func paragraphXML(
        blockStyle: BlockStyle,
        contentRange: NSRange,
        in attributed: NSAttributedString,
        decimalNumId: Int
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
                let runText = (attributed.string as NSString).substring(with: runRange)
                runs += runXML(text: runText, traits: attrs.inlineTraits)
            }
        }

        let propertiesXML = properties.isEmpty ? "" : "<w:pPr>\(properties)</w:pPr>"
        return "<w:p>\(propertiesXML)\(runs)</w:p>"
    }

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

    private var contentTypesXML: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
        <Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>
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

    private func documentXML(body: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <w:body>\(body)<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr></w:body>
        </w:document>
        """
    }

    private var stylesXML: String {
        var styles = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <w:docDefaults><w:rPrDefault><w:rPr>\(runFontsXML(for: configuration.paragraph))</w:rPr></w:rPrDefault></w:docDefaults>
        <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/>\(paragraphPropertiesXML(for: configuration.paragraph))<w:rPr>\(runFontsXML(for: configuration.paragraph))</w:rPr></w:style>
        """

        for level in 1...6 {
            let style = configuration.styleForHeading(level: level)
            styles += """
            <w:style w:type="paragraph" w:styleId="Heading\(level)"><w:name w:val="heading \(level)"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:pPr><w:outlineLvl w:val="\(level - 1)"/>\(spacingXML(for: style))</w:pPr><w:rPr>\(runFontsXML(for: style))\(style.fontWeight.isBoldForExport ? "<w:b/>" : "")\(style.isItalic ? "<w:i/>" : "")</w:rPr></w:style>
            """
        }

        styles += """
        <w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/><w:basedOn w:val="Normal"/><w:pPr><w:ind w:left="720"/>\(spacingXML(for: configuration.blockquote))</w:pPr><w:rPr>\(runFontsXML(for: configuration.blockquote))\(configuration.blockquote.isItalic ? "<w:i/>" : "")<w:color w:val="595959"/></w:rPr></w:style>
        <w:style w:type="paragraph" w:styleId="CodeBlock"><w:name w:val="Code Block"/><w:basedOn w:val="Normal"/><w:pPr>\(spacingXML(for: configuration.code))<w:shd w:val="clear" w:color="auto" w:fill="F2F2F2"/></w:pPr><w:rPr>\(runFontsXML(for: configuration.code))</w:rPr></w:style>
        <w:style w:type="paragraph" w:styleId="ListParagraph"><w:name w:val="List Paragraph"/><w:basedOn w:val="Normal"/><w:pPr><w:ind w:left="720"/></w:pPr></w:style>
        </w:styles>
        """
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
        let before = Int(style.paragraphSpacingBefore * 20)
        let after = Int(style.paragraphSpacingAfter * 20)
        return "<w:spacing w:before=\"\(before)\" w:after=\"\(after)\"/>"
    }

    private func runFontsXML(for style: ElementStyle) -> String {
        let family = escapeXML(exportFontName(for: style.fontFamily))
        let halfPoints = Int(style.fontSize * 2)
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
