import Foundation

// MARK: - Public context type

/// Carries bibliographic data needed for Word-native citation/bibliography export.
/// Pass to `DocxExporter.init(configuration:references:)` to activate DOCX export
/// of `b:Sources` customXml, CITATION field SDTs, and BIBLIOGRAPHY field SDT.
struct ReferenceExportContext {
    /// All items available in the document's reference store.
    var items: [CSLItem]
    /// The active CSL style identifier (informational only; Word uses its own engine).
    var styleID: String
}

// MARK: - Tag registry

/// Produces Word-compatible tag strings (alphanumeric, start with letter, ≤32 chars)
/// and guarantees uniqueness within one export session.
final class WordTagRegistry {
    private var used: Set<String> = []
    private var cache: [String: String] = [:]

    func tag(for citekey: String) -> String {
        if let cached = cache[citekey] { return cached }
        let raw = sanitizeTag(citekey)
        var candidate = raw
        var suffix = 2
        while used.contains(candidate) {
            let base = String(raw.prefix(29))   // leave room for "999"
            candidate = "\(base)\(suffix)"
            suffix += 1
        }
        used.insert(candidate)
        cache[citekey] = candidate
        return candidate
    }

    private func sanitizeTag(_ key: String) -> String {
        // Keep only alphanumeric ASCII; replace others with underscore.
        var result = ""
        for ch in key.unicodeScalars {
            if ch.value < 128, (CharacterSet.alphanumerics.contains(ch)) {
                result.append(Character(ch))
            }
        }
        // Must start with a letter.
        if result.isEmpty || !result.first!.isLetter {
            result = "ref" + result
        }
        // 32-char limit.
        return String(result.prefix(32))
    }
}

// MARK: - Deterministic GUID

/// Produces a stable uppercase braced UUID for a given citekey, using a simple
/// hash-based approach so re-exports produce the same GUID (Word uses it for
/// identity checking in Manage Sources).
func deterministicGUID(for citekey: String) -> String {
    // Mix citekey bytes into a 128-bit value using a simple xorshift approach.
    var h0: UInt64 = 0x6C62272E07BB0142
    var h1: UInt64 = 0x62B821756295C58D
    for byte in citekey.utf8 {
        h0 = h0 &* 6364136223846793005 &+ UInt64(byte)
        h1 = h1 ^ h0
        h0 = h0 ^ (h0 >> 33)
        h1 = h1 &+ (h1 >> 27)
    }
    // Set version 4 and variant bits.
    h0 = (h0 & 0xFFFFFFFFFFFF0FFF) | 0x0000000000004000
    h1 = (h1 & 0x3FFFFFFFFFFFFFFF) | 0x8000000000000000

    func hex(_ v: UInt64, _ bits: Int) -> String {
        String(format: "%0\(bits / 4)X", v)
    }

    let a = hex(h0 >> 32, 32)                                   // 8 hex
    let b = hex((h0 >> 16) & 0xFFFF, 16)                        // 4 hex
    let c = hex(h0 & 0xFFFF, 16)                                // 4 hex
    let d = hex(h1 >> 48, 16)                                   // 4 hex
    let e = hex(h1 & 0x0000FFFFFFFFFFFF, 48)                    // 12 hex

    return "{\(a)-\(b)-\(c)-\(d)-\(e)}"
}

// MARK: - CSL → Word type mapping

func wordSourceType(for cslType: String) -> String {
    switch cslType {
    case "article-journal":     return "JournalArticle"
    case "book":                return "Book"
    case "chapter":             return "BookSection"
    case "paper-conference":    return "ConferenceProceedings"
    case "webpage":             return "InternetSite"
    case "article-newspaper":   return "ArticleInAPeriodical"
    case "report", "thesis":    return "Report"
    default:                    return "Misc"
    }
}

// MARK: - b:Source XML builder

/// Produces the `<b:Source>` XML element for one CSLItem.
/// Child order follows the Word OOXML schema sequence strictly.
func bSourceXML(for item: CSLItem, tag: String, escaping escape: (String) -> String) -> String {
    var xml = "<b:Source>"

    // Schema order: Tag, SourceType, Guid, Author block, Title, Year,
    // City, Publisher, JournalName, Volume, Issue, Pages, StandardNumber, URL.

    xml += "<b:Tag>\(escape(tag))</b:Tag>"
    xml += "<b:SourceType>\(wordSourceType(for: item.type))</b:SourceType>"
    xml += "<b:Guid>\(escape(deterministicGUID(for: item.id)))</b:Guid>"

    // Author block — only emit if we have at least one author.
    let authors = item.authors
    if !authors.isEmpty {
        xml += "<b:Author><b:Author><b:NameList>"
        for author in authors {
            xml += "<b:Person>"
            if !author.family.isEmpty {
                xml += "<b:Last>\(escape(author.family))</b:Last>"
            }
            if !author.given.isEmpty {
                xml += "<b:First>\(escape(author.given))</b:First>"
            }
            xml += "</b:Person>"
        }
        xml += "</b:NameList></b:Author></b:Author>"
    }

    let title = item.title
    if !title.isEmpty {
        xml += "<b:Title>\(escape(title))</b:Title>"
    }

    if let year = item.issuedYear {
        xml += "<b:Year>\(year)</b:Year>"
    }

    // City — CSL "publisher-place"
    if let city = item.fields["publisher-place"]?.stringValue, !city.isEmpty {
        xml += "<b:City>\(escape(city))</b:City>"
    }

    // Publisher
    if let pub = item.fields["publisher"]?.stringValue, !pub.isEmpty {
        xml += "<b:Publisher>\(escape(pub))</b:Publisher>"
    }

    // JournalName — CSL "container-title"
    if let journal = item.containerTitle, !journal.isEmpty {
        xml += "<b:JournalName>\(escape(journal))</b:JournalName>"
    }

    // Volume
    if let vol = item.fields["volume"]?.stringValue, !vol.isEmpty {
        xml += "<b:Volume>\(escape(vol))</b:Volume>"
    }

    // Issue
    if let issue = item.fields["issue"]?.stringValue, !issue.isEmpty {
        xml += "<b:Issue>\(escape(issue))</b:Issue>"
    }

    // Pages
    if let pages = item.fields["page"]?.stringValue, !pages.isEmpty {
        xml += "<b:Pages>\(escape(pages))</b:Pages>"
    }

    // StandardNumber — DOI
    if let doi = item.doi, !doi.isEmpty {
        xml += "<b:StandardNumber>\(escape(doi))</b:StandardNumber>"
    }

    // URL
    if let url = item.url, !url.isEmpty {
        xml += "<b:URL>\(escape(url))</b:URL>"
    }

    xml += "</b:Source>"
    return xml
}

// MARK: - Full customXml package builder

struct WordBibliographyPackage {
    /// `customXml/item1.xml` content.
    let item1XML: String
    /// `customXml/itemProps1.xml` content.
    let itemProps1XML: String
    /// `customXml/_rels/item1.xml.rels` content.
    let itemRelsXML: String
}

/// The datastoreItem ID used for the bibliography customXml item.
/// Must be a stable GUID so Word recognises the part.
private let datastoreItemID = "{B9B0CE3C-8A8B-4B1A-870E-7D8B0C7E1234}"

func buildBibliographyPackage(
    citing items: [CSLItem],
    tagRegistry: inout WordTagRegistry,
    escaping escape: (String) -> String
) -> WordBibliographyPackage {
    var sourcesXML = ""
    for item in items {
        let tag = tagRegistry.tag(for: item.id)
        sourcesXML += bSourceXML(for: item, tag: tag, escaping: escape)
    }

    let item1 = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <b:Sources xmlns:b="http://schemas.openxmlformats.org/officeDocument/2006/bibliography" SelectedStyle="" StyleName="" xmlns="http://schemas.openxmlformats.org/officeDocument/2006/bibliography">\(sourcesXML)</b:Sources>
    """

    let itemProps1 = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <ds:datastoreItem ds:itemID="\(datastoreItemID)" xmlns:ds="http://schemas.openxmlformats.org/officeDocument/2006/customXml"><ds:schemaRefs><ds:schemaRef ds:uri="http://schemas.openxmlformats.org/officeDocument/2006/bibliography"/></ds:schemaRefs></ds:datastoreItem>
    """

    // item1.xml.rels — item1.xml → itemProps1.xml
    let itemRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/customXmlProps" Target="itemProps1.xml"/></Relationships>
    """

    return WordBibliographyPackage(
        item1XML: item1,
        itemProps1XML: itemProps1,
        itemRelsXML: itemRels
    )
}

// MARK: - Hyperlink detection helpers

struct HyperlinkSpan {
    let range: NSRange
    let url: String
}

/// Find all http(s) URL spans in a plain string.
func findHyperlinkSpans(in text: String) -> [HyperlinkSpan] {
    var spans: [HyperlinkSpan] = []
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
        return spans
    }
    let nsText = text as NSString
    let range = NSRange(location: 0, length: nsText.length)
    let matches = detector.matches(in: text, options: [], range: range)
    for match in matches {
        guard let url = match.url, url.scheme == "http" || url.scheme == "https" else { continue }
        spans.append(HyperlinkSpan(range: match.range, url: url.absoluteString))
    }
    return spans
}
