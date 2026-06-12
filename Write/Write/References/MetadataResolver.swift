import Foundation

// MARK: - MetadataResolver

nonisolated struct MetadataResolver {

    // MARK: Input

    enum Input {
        case doi(String)
        case arxiv(String)
        case isbn(String)
        case url(URL)
    }

    // MARK: Errors

    enum ResolverError: Error, LocalizedError {
        case noUsableMetadata(String)
        case networkError(String)
        case decodingError(String)

        var errorDescription: String? {
            switch self {
            case .noUsableMetadata(let r): return "No usable metadata: \(r)"
            case .networkError(let r):    return "Network error: \(r)"
            case .decodingError(let r):   return "Decoding error: \(r)"
            }
        }
    }

    // MARK: - detect

    static func detect(_ string: String) -> Input? {
        var s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = s.last, ".,;:)]}'\"".contains(last) { s = String(s.dropLast()) }
        guard !s.isEmpty else { return nil }

        // An arXiv link is the more specific form of its URL, and a DOI
        // embedded ANYWHERE (doi.org links, publisher URLs like
        // science.org/doi/10.1126/…, "doi:10.x/y" prefixes, surrounding
        // prose) beats scraping the page.
        if let id = extractArXivFromURL(s) { return .arxiv(id) }
        if let doi = extractEmbeddedDOI(s) { return .doi(doi) }
        if matchesArXivID(s) { return .arxiv(s) }
        if let isbn = normalizedISBN(s) { return .isbn(isbn) }
        if let url = URL(string: s), url.scheme == "http" || url.scheme == "https" {
            return .url(url)
        }
        return nil
    }

    /// A specific, actionable message for input `detect` rejected.
    static func detectionHint(_ string: String) -> String {
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let prefix = incompleteDOIPrefix(s) {
            return "“\(prefix)” is only a DOI prefix — the full DOI continues "
                + "after a slash (like \(prefix)/abc123). Paste the complete "
                + "DOI or the article's URL."
        }
        return "Couldn't find a DOI, URL, ISBN, or arXiv ID. Paste the full "
            + "link or identifier."
    }

    // MARK: - resolve

    func resolve(_ input: Input) async throws -> CSLItem {
        switch input {
        case .doi(let doi):    return try await resolveDOI(doi)
        case .arxiv(let id):  return try await resolveArXiv(id)
        case .isbn(let isbn): return try await resolveISBN(isbn)
        case .url(let url):   return try await resolveURL(url)
        }
    }

    /// Detect-and-resolve with fallbacks: a DOI extracted from a publisher
    /// URL that fails to resolve (over-captured suffix, registry hiccup)
    /// falls back to scraping the page itself.
    func resolve(string: String) async throws -> CSLItem {
        guard let input = Self.detect(string) else {
            throw ResolverError.noUsableMetadata(Self.detectionHint(string))
        }
        do {
            return try await resolve(input)
        } catch {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if case .doi = input,
               let url = URL(string: trimmed),
               url.scheme == "http" || url.scheme == "https",
               let fromPage = try? await resolve(.url(url)) {
                return fromPage
            }
            throw error
        }
    }
}

// MARK: - Detection helpers (file-private)

/// Finds a full DOI anywhere in the string — bare, `doi:`-prefixed, on a
/// doi.org link, or buried in a publisher URL path — and trims URL
/// artifacts (queries, fragments, `/full`-style viewer suffixes) off it.
private nonisolated func extractEmbeddedDOI(_ s: String) -> String? {
    guard let range = s.range(of: #"10\.\d{4,9}/[^\s"<>]+"#, options: .regularExpression) else {
        return nil
    }
    var doi = String(s[range])

    if let cut = doi.firstIndex(where: { $0 == "?" || $0 == "#" }) {
        doi = String(doi[..<cut])
    }
    while let last = doi.last, ".,;:)]}'\"/".contains(last) {
        doi.removeLast()
    }
    // Publisher viewer pages append path segments after the DOI itself.
    let viewerSuffixes = ["/full", "/abstract", "/pdf", "/epdf", "/html", "/meta", "/summary"]
    var stripped = true
    while stripped {
        stripped = false
        for suffix in viewerSuffixes where doi.lowercased().hasSuffix(suffix) {
            doi = String(doi.dropLast(suffix.count))
            stripped = true
        }
    }

    return matchesDOI(doi) ? doi : nil
}

/// A `10.NNNN` registrant prefix with no article suffix — not resolvable,
/// but worth a precise hint instead of a generic failure.
private nonisolated func incompleteDOIPrefix(_ s: String) -> String? {
    guard s.range(of: #"10\.\d{4,9}/[^\s"<>]+"#, options: .regularExpression) == nil,
          let range = s.range(of: #"10\.\d{4,9}"#, options: .regularExpression)
    else { return nil }
    return String(s[range])
}

private nonisolated func extractArXivFromURL(_ s: String) -> String? {
    // new-style: YYYY.NNNNN
    if let id = firstCaptureGroup(in: s,
        pattern: #"arxiv\.org/(?:abs|pdf)/(\d{4}\.\d{4,5}(?:v\d+)?)"#,
        options: [.regularExpression, .caseInsensitive]) { return id }
    // old-style: archive/NNNNN
    if let id = firstCaptureGroup(in: s,
        pattern: #"arxiv\.org/(?:abs|pdf)/([a-z\-]+/\d+(?:v\d+)?)"#,
        options: [.regularExpression, .caseInsensitive]) { return id }
    return nil
}

private nonisolated func matchesDOI(_ s: String) -> Bool {
    s.range(of: #"^10\.\d{4,9}/.+"#, options: .regularExpression) != nil
}

private nonisolated func matchesArXivID(_ s: String) -> Bool {
    s.range(of: #"^\d{4}\.\d{4,5}(?:v\d+)?$"#, options: .regularExpression) != nil
}

private nonisolated func normalizedISBN(_ s: String) -> String? {
    let digits = s.filter(\.isNumber)
    guard digits.count == 10 || digits.count == 13 else { return nil }
    if digits.count == 13 && !digits.hasPrefix("978") && !digits.hasPrefix("979") { return nil }
    // require that the original had only digits, spaces, or hyphens (no other letters)
    let stripped = s.filter { !$0.isNumber && $0 != "-" && $0 != " " }
    guard stripped.isEmpty else { return nil }
    return digits
}

// MARK: - DOI

private nonisolated func resolveDOI(_ doi: String) async throws -> CSLItem {
    let encoded = doi.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? doi
    guard let url = URL(string: "https://doi.org/\(encoded)") else {
        throw MetadataResolver.ResolverError.networkError("Invalid DOI URL")
    }
    var req = URLRequest(url: url, timeoutInterval: 15)
    req.setValue("application/vnd.citationstyles.csl+json", forHTTPHeaderField: "Accept")
    let (data, resp) = try await URLSession.shared.data(for: req)
    guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        throw MetadataResolver.ResolverError.networkError("DOI server returned non-200")
    }
    do {
        var item = try JSONDecoder().decode(CSLItem.self, from: data)
        // Registry payloads carry no citekey (the decoder substitutes a
        // UUID); blank it so the store generates a readable "smith2020".
        item.id = ""
        return item
    } catch {
        throw MetadataResolver.ResolverError.decodingError("CSL-JSON decode failed: \(error)")
    }
}

// MARK: - arXiv

private nonisolated func resolveArXiv(_ id: String) async throws -> CSLItem {
    let baseID = id.range(of: #"v\d+$"#, options: .regularExpression).map { String(id[..<$0.lowerBound]) } ?? id
    guard let url = URL(string: "https://export.arxiv.org/api/query?id_list=\(baseID)&max_results=1") else {
        throw MetadataResolver.ResolverError.networkError("Invalid arXiv URL")
    }
    let (data, resp) = try await URLSession.shared.data(from: url)
    guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        throw MetadataResolver.ResolverError.networkError("arXiv API returned non-200")
    }
    guard let xml = String(data: data, encoding: .utf8) else {
        throw MetadataResolver.ResolverError.decodingError("arXiv response not UTF-8")
    }
    return try parseArXivAtom(xml, requestedID: id)
}

private nonisolated func parseArXivAtom(_ xml: String, requestedID: String) throws -> CSLItem {
    guard let entryStart = xml.range(of: "<entry>"),
          let entryEnd   = xml.range(of: "</entry>", range: entryStart.upperBound..<xml.endIndex) else {
        throw MetadataResolver.ResolverError.noUsableMetadata("No <entry> in arXiv response")
    }
    let entry = String(xml[entryStart.lowerBound..<entryEnd.upperBound])

    let title = cleanText(tagContent("title", in: entry) ?? "")
    guard !title.isEmpty else {
        throw MetadataResolver.ResolverError.noUsableMetadata("No title in arXiv entry")
    }

    var authors: [(family: String, given: String)] = []
    var pos = entry.startIndex..<entry.endIndex
    while let aStart = entry.range(of: "<author>", range: pos),
          let aEnd = entry.range(of: "</author>", range: aStart.upperBound..<entry.endIndex) {
        let block = String(entry[aStart.lowerBound..<aEnd.upperBound])
        if let name = tagContent("name", in: block) { authors.append(splitName(name)) }
        pos = aEnd.upperBound..<entry.endIndex
    }

    var year: Int?
    if let pub = tagContent("published", in: entry) {
        year = Int(pub.prefix(4))
    }

    var doiValue: String?
    if let r = entry.range(of: #"<arxiv:doi[^>]*>"#, options: .regularExpression),
       let e = entry.range(of: "</arxiv:doi>", range: r.upperBound..<entry.endIndex) {
        let v = String(entry[r.upperBound..<e.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !v.isEmpty { doiValue = v }
    }

    var fields: [String: JSONValue] = [
        "type":   .string("article"),
        "title":  .string(title),
        "URL":    .string("https://arxiv.org/abs/\(requestedID)"),
        "number": .string("arXiv:\(requestedID)"),
        "note":   .string("arXiv:\(requestedID)"),
        "source": .string("arXiv"),
    ]
    if !authors.isEmpty {
        fields["author"] = .array(authors.map { .object(["family": .string($0.family), "given": .string($0.given)]) })
    }
    if let y = year { fields["issued"] = issuedFromYear(y) }
    if let d = doiValue { fields["DOI"] = .string(d) }

    return CSLItem(id: "arxiv_\(requestedID.replacing(".", with: "_"))", fields: fields)
}

// MARK: - ISBN

private nonisolated func resolveISBN(_ isbn: String) async throws -> CSLItem {
    guard let url = URL(string: "https://openlibrary.org/api/books?bibkeys=ISBN:\(isbn)&format=json&jscmd=data") else {
        throw MetadataResolver.ResolverError.networkError("Invalid OpenLibrary URL")
    }
    let (data, resp) = try await URLSession.shared.data(from: url)
    guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        throw MetadataResolver.ResolverError.networkError("OpenLibrary returned non-200")
    }
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let book = json["ISBN:\(isbn)"] as? [String: Any] else {
        throw MetadataResolver.ResolverError.noUsableMetadata("ISBN not found in OpenLibrary")
    }

    guard let rawTitle = book["title"] as? String else {
        throw MetadataResolver.ResolverError.noUsableMetadata("No title in OpenLibrary response")
    }

    var fields: [String: JSONValue] = [
        "type":  .string("book"),
        "title": .string(decodeHTMLEntities(rawTitle)),
        "ISBN":  .string(isbn),
    ]

    if let rawAuthors = book["authors"] as? [[String: Any]] {
        let authors: [JSONValue] = rawAuthors.compactMap { a in
            guard let name = a["name"] as? String else { return nil }
            let s = splitName(name)
            return .object(["family": .string(s.family), "given": .string(s.given)])
        }
        if !authors.isEmpty { fields["author"] = .array(authors) }
    }

    if let pubDate = book["publish_date"] as? String, let y = extractYear(from: pubDate) {
        fields["issued"] = issuedFromYear(y)
    }

    if let pubs = book["publishers"] as? [[String: Any]],
       let name = pubs.first?["name"] as? String {
        fields["publisher"] = .string(name)
    }

    if let pages = book["number_of_pages"] as? Int {
        fields["number-of-pages"] = .number(Double(pages))
    }

    if let olURL = book["url"] as? String { fields["URL"] = .string(olURL) }

    return CSLItem(id: "isbn_\(isbn)", fields: fields)
}

// MARK: - URL

private nonisolated func resolveURL(_ url: URL) async throws -> CSLItem {
    var req = URLRequest(url: url, timeoutInterval: 10)
    req.setValue(
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
        "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        forHTTPHeaderField: "User-Agent"
    )
    req.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

    let (raw, resp) = try await URLSession.shared.data(for: req)
    guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        throw MetadataResolver.ResolverError.networkError("URL fetch returned non-200")
    }

    let slice = raw.count > 2_097_152 ? raw.prefix(2_097_152) : raw[...]
    let html = String(data: Data(slice), encoding: .utf8)
           ?? String(data: Data(slice), encoding: .isoLatin1)
           ?? ""
    guard !html.isEmpty else { throw MetadataResolver.ResolverError.noUsableMetadata("Empty response") }

    let finalURL = (resp.url ?? url).absoluteString
    return try buildURLItem(from: html, url: finalURL)
}

private nonisolated func buildURLItem(from html: String, url: String) throws -> CSLItem {
    if let item = extractHighwireMeta(html, url: url) { return item }
    if let item = extractJSONLD(html, url: url)        { return item }
    if let item = extractOpenGraph(html, url: url)     { return item }

    if let title = extractHTMLTitle(html), !title.isEmpty {
        return CSLItem(id: "url_\(abs(url.hashValue))", fields: [
            "type":     .string("webpage"),
            "title":    .string(title),
            "URL":      .string(url),
            "accessed": accessedDateValue(),
        ])
    }
    throw MetadataResolver.ResolverError.noUsableMetadata("No title or structured metadata found")
}

// MARK: - Highwire meta tags

private nonisolated func extractHighwireMeta(_ html: String, url: String) -> CSLItem? {
    let metas = allMetaTags(html)
    guard let title = metas["citation_title"] else { return nil }

    var fields: [String: JSONValue] = [
        "type":     .string("article-journal"),
        "title":    .string(title),
        "URL":      .string(url),
        "accessed": accessedDateValue(),
    ]

    let authors = allMetaTagsMulti(html, name: "citation_author")
    if !authors.isEmpty {
        fields["author"] = .array(authors.map { n in
            let s = splitName(n)
            return .object(["family": .string(s.family), "given": .string(s.given)])
        })
    }

    if let j = metas["citation_journal_title"] { fields["container-title"] = .string(j) }
    if let d = metas["citation_doi"]            { fields["DOI"] = .string(d) }
    if let v = metas["citation_volume"]         { fields["volume"] = .string(v) }
    if let i = metas["citation_issue"]          { fields["issue"] = .string(i) }

    let fp = metas["citation_firstpage"], lp = metas["citation_lastpage"]
    if let f = fp, let l = lp { fields["page"] = .string("\(f)-\(l)") }
    else if let f = fp         { fields["page"] = .string(f) }

    let dateStr = metas["citation_publication_date"] ?? metas["citation_date"]
    if let ds = dateStr, let y = extractYear(from: ds) { fields["issued"] = issuedFromYear(y) }

    return CSLItem(id: "url_\(abs(url.hashValue))", fields: fields)
}

// MARK: - JSON-LD

private nonisolated func extractJSONLD(_ html: String, url: String) -> CSLItem? {
    let pattern = #"<script[^>]+type\s*=\s*["']application/ld\+json["'][^>]*>"#
    var pos = html.startIndex..<html.endIndex
    while let open = html.range(of: pattern, options: [.regularExpression, .caseInsensitive], range: pos) {
        guard let close = html.range(of: "</script>", options: .caseInsensitive,
                                      range: open.upperBound..<html.endIndex) else { break }
        let jsonText = String(html[open.upperBound..<close.lowerBound])
        pos = close.upperBound..<html.endIndex

        guard let data = jsonText.data(using: .utf8),
              let obj  = try? JSONSerialization.jsonObject(with: data) else { continue }

        let candidates: [[String: Any]]
        if let arr    = obj as? [[String: Any]] { candidates = arr }
        else if let s = obj as? [String: Any]   { candidates = [s] }
        else                                     { continue }

        for c in candidates {
            if let item = buildItemFromJSONLD(c, url: url) { return item }
        }
    }
    return nil
}

private nonisolated func buildItemFromJSONLD(_ obj: [String: Any], url: String) -> CSLItem? {
    let typeRaw = obj["@type"] as? String ?? ""
    let supported = ["Article", "NewsArticle", "BlogPosting", "ScholarlyArticle",
                     "TechArticle", "WebPage", "WebSite"]
    guard supported.contains(typeRaw) else { return nil }

    // Prefer headline for news types; for other types prefer name (Wikipedia pattern)
    let headline = obj["headline"] as? String ?? ""
    let name     = obj["name"] as? String ?? ""
    let rawTitle: String
    if typeRaw == "NewsArticle" {
        rawTitle = headline.isEmpty ? name : headline
    } else {
        rawTitle = name.isEmpty ? headline : name
    }
    let title = decodeHTMLEntities(rawTitle)
    guard !title.isEmpty else { return nil }

    let isNews = typeRaw == "NewsArticle"
    let cslType = isNews ? "article-newspaper" : "webpage"

    var fields: [String: JSONValue] = [
        "type":     .string(cslType),
        "title":    .string(title),
        "URL":      .string(url),
        "accessed": accessedDateValue(),
    ]

    let pubName: String?
    if let p = obj["publisher"] as? [String: Any] { pubName = p["name"] as? String }
    else                                            { pubName = obj["publisher"] as? String }
    if let p = pubName {
        fields["container-title"] = .string(p)
        if isNews { fields["publisher"] = .string(p) }
    }

    let authorRaw = obj["author"]
    if let arr = authorRaw as? [[String: Any]] {
        let list: [JSONValue] = arr.compactMap { a in
            guard let name = a["name"] as? String, !name.isEmpty else { return nil }
            let s = splitName(name)
            return .object(["family": .string(s.family), "given": .string(s.given)])
        }
        if !list.isEmpty { fields["author"] = .array(list) }
    } else if let single = authorRaw as? [String: Any], let name = single["name"] as? String {
        let s = splitName(name)
        fields["author"] = .array([.object(["family": .string(s.family), "given": .string(s.given)])])
    } else if let name = authorRaw as? String {
        let s = splitName(name)
        fields["author"] = .array([.object(["family": .string(s.family), "given": .string(s.given)])])
    }

    if let ds = obj["datePublished"] as? String, let y = extractYear(from: ds) {
        fields["issued"] = issuedFromYear(y)
    }

    return CSLItem(id: "url_\(abs(url.hashValue))", fields: fields)
}

// MARK: - OpenGraph

private nonisolated func extractOpenGraph(_ html: String, url: String) -> CSLItem? {
    let metas = allMetaTags(html)
    guard let title = metas["og:title"] else { return nil }

    let ogType   = metas["og:type"] ?? ""
    let siteName = metas["og:site_name"]
    let isArticle = ogType == "article"
    let cslType = (isArticle && siteName != nil) ? "article-newspaper" : "webpage"

    var fields: [String: JSONValue] = [
        "type":     .string(cslType),
        "title":    .string(title),
        "URL":      .string(metas["og:url"] ?? url),
        "accessed": accessedDateValue(),
    ]
    if let s = siteName {
        fields["container-title"] = .string(s)
        if cslType == "article-newspaper" { fields["publisher"] = .string(s) }
    }
    if let author = metas["article:author"] ?? metas["og:author"] {
        let s = splitName(author)
        fields["author"] = .array([.object(["family": .string(s.family), "given": .string(s.given)])])
    }
    if let ds = metas["article:published_time"] ?? metas["og:article:published_time"],
       let y = extractYear(from: ds) {
        fields["issued"] = issuedFromYear(y)
    }

    return CSLItem(id: "url_\(abs(url.hashValue))", fields: fields)
}

// MARK: - HTML helpers

private nonisolated func extractHTMLTitle(_ html: String) -> String? {
    guard let s = html.range(of: "<title", options: .caseInsensitive),
          let o = html[s.upperBound...].range(of: ">"),
          let e = html.range(of: "</title>", options: .caseInsensitive) else { return nil }
    let raw = String(html[o.upperBound..<e.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    return decodeHTMLEntities(raw)
}

/// Returns a dict of all <meta name/property="key" content="val"> tags (last writer wins per key).
private nonisolated func allMetaTags(_ html: String) -> [String: String] {
    var result: [String: String] = [:]
    var pos = html.startIndex..<html.endIndex
    while let r = html.range(of: #"<meta\b[^>]+/?>"#, options: [.regularExpression, .caseInsensitive], range: pos) {
        let tag = String(html[r])
        if let key = metaKey(tag), let val = metaContent(tag) {
            result[key.lowercased()] = val
        }
        pos = r.upperBound..<html.endIndex
    }
    return result
}

/// Returns all content values for tags whose name/property matches `name`.
private nonisolated func allMetaTagsMulti(_ html: String, name: String) -> [String] {
    var result: [String] = []
    var pos = html.startIndex..<html.endIndex
    while let r = html.range(of: #"<meta\b[^>]+/?>"#, options: [.regularExpression, .caseInsensitive], range: pos) {
        let tag = String(html[r])
        if let k = metaKey(tag), k.lowercased() == name.lowercased(), let v = metaContent(tag) {
            result.append(v)
        }
        pos = r.upperBound..<html.endIndex
    }
    return result
}

private nonisolated func metaKey(_ tag: String) -> String? {
    for attr in ["name", "property"] {
        // match attr="value" or attr='value'
        let pat = "\(attr)\\s*=\\s*\"([^\"]+)\""
        if let r = tag.range(of: pat, options: [.regularExpression, .caseInsensitive]) {
            let sub = String(tag[r])
            if let vr = sub.range(of: "\"([^\"]+)\"", options: .regularExpression) {
                var v = String(sub[vr]); v.removeFirst(); v.removeLast()
                return v
            }
        }
        let pat2 = "\(attr)\\s*=\\s*'([^']+)'"
        if let r = tag.range(of: pat2, options: [.regularExpression, .caseInsensitive]) {
            let sub = String(tag[r])
            if let vr = sub.range(of: "'([^']+)'", options: .regularExpression) {
                var v = String(sub[vr]); v.removeFirst(); v.removeLast()
                return v
            }
        }
    }
    return nil
}

private nonisolated func metaContent(_ tag: String) -> String? {
    // double-quoted content
    if let r = tag.range(of: #"content\s*=\s*"([^"]*)"#, options: .regularExpression) {
        let sub = String(tag[r])
        if let inner = sub.range(of: "\"([^\"]*)\"", options: .regularExpression) {
            var v = String(sub[inner])
            v.removeFirst(); v.removeLast()
            return decodeHTMLEntities(v)
        }
    }
    // single-quoted content
    if let r = tag.range(of: #"content\s*=\s*'([^']*)'"#, options: .regularExpression) {
        let sub = String(tag[r])
        if let inner = sub.range(of: "'([^']*)'", options: .regularExpression) {
            var v = String(sub[inner])
            v.removeFirst(); v.removeLast()
            return decodeHTMLEntities(v)
        }
    }
    return nil
}

// MARK: - XML tag content helper

/// Returns the text content of the first occurrence of <tag>…</tag> in `s`.
private nonisolated func tagContent(_ tag: String, in s: String) -> String? {
    guard let open = s.range(of: "<\(tag)", options: .caseInsensitive),
          let closeAngle = s[open.upperBound...].range(of: ">"),
          let closeTag   = s.range(of: "</\(tag)>", options: .caseInsensitive) else { return nil }
    let textStart = closeAngle.upperBound
    guard textStart <= closeTag.lowerBound else { return nil }
    return String(s[textStart..<closeTag.lowerBound])
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - HTML entity decoding

nonisolated func decodeHTMLEntities(_ s: String) -> String {
    var r = s
    let named: [(String, String)] = [
        ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
        ("&apos;", "'"), ("&#x27;", "'"), ("&#39;", "'"), ("&nbsp;", " "),
        ("&ndash;", "–"), ("&mdash;", "—"), ("&lsquo;", "'"), ("&rsquo;", "'"),
        ("&ldquo;", "\u{201C}"), ("&rdquo;", "\u{201D}"), ("&hellip;", "…"),
        ("&copy;", "©"), ("&reg;", "®"), ("&trade;", "™"),
    ]
    for (entity, repl) in named { r = r.replacingOccurrences(of: entity, with: repl) }
    r = replaceEntityMatches(r, pattern: #"&#(\d+);"#) { digits in
        guard let code = UInt32(digits), let scalar = Unicode.Scalar(code) else { return nil }
        return String(Character(scalar))
    }
    r = replaceEntityMatches(r, pattern: #"&#x([0-9a-fA-F]+);"#) { hex in
        guard let code = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(code) else { return nil }
        return String(Character(scalar))
    }
    return r
}

// MARK: - Shared helpers

private nonisolated func splitName(_ fullName: String) -> (family: String, given: String) {
    let parts = fullName.trimmingCharacters(in: .whitespaces).split(separator: " ")
    guard parts.count >= 2 else { return (family: fullName, given: "") }
    return (family: String(parts.last!), given: parts.dropLast().joined(separator: " "))
}

private nonisolated func cleanText(_ s: String) -> String {
    var result = s
    // collapse whitespace
    while result.range(of: "  ", options: .literal) != nil {
        result = result.replacingOccurrences(of: "  ", with: " ")
    }
    result = result.replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\r", with: " ")
        .replacingOccurrences(of: "\t", with: " ")
    return decodeHTMLEntities(result.trimmingCharacters(in: .whitespacesAndNewlines))
}

private nonisolated func extractYear(from s: String) -> Int? {
    firstCaptureGroup(in: s, pattern: #"(\d{4})"#, options: .regularExpression).flatMap { Int($0) }
}

private nonisolated func issuedFromYear(_ year: Int) -> JSONValue {
    .object(["date-parts": .array([.array([.number(Double(year))])])])
}

private nonisolated func accessedDateValue() -> JSONValue {
    let cal = Calendar.current
    let now = Date()
    let y = cal.component(.year, from: now)
    let mo = cal.component(.month, from: now)
    let d = cal.component(.day, from: now)
    return .object(["date-parts": .array([.array([.number(Double(y)), .number(Double(mo)), .number(Double(d))])])])
}

// MARK: - NSRegularExpression helpers

/// Returns the content of capture group 1 from the first match of `pattern` in `s`.
private nonisolated func firstCaptureGroup(
    in s: String,
    pattern: String,
    options: NSString.CompareOptions = .regularExpression
) -> String? {
    // Use NSRegularExpression to extract capture group 1
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
          let m = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
          m.numberOfRanges > 1 else { return nil }
    let r = m.range(at: 1)
    guard let range = Range(r, in: s) else { return nil }
    return String(s[range])
}

/// Replaces all matches of `pattern` in `s`, feeding capture group 1 to `transform`.
/// If `transform` returns nil, the original match text is preserved.
private nonisolated func replaceEntityMatches(
    _ s: String,
    pattern: String,
    transform: (String) -> String?
) -> String {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
    let ns = s as NSString
    let matches = regex.matches(in: s, range: NSRange(s.startIndex..., in: s))
    var result = ""
    var lastEnd = s.startIndex
    for match in matches {
        guard let fullRange = Range(match.range, in: s) else { continue }
        result += s[lastEnd..<fullRange.lowerBound]
        let captured: String
        if match.numberOfRanges > 1, let gr = Range(match.range(at: 1), in: s) {
            captured = String(s[gr])
        } else {
            captured = String(ns.substring(with: match.range))
        }
        result += transform(captured) ?? String(s[fullRange])
        lastEnd = fullRange.upperBound
    }
    result += s[lastEnd...]
    return result
}

// MARK: - Bibliographic search (Crossref)

extension MetadataResolver {
    /// Free-text bibliographic search via Crossref's public REST API — the
    /// same class of open scholarly service citation generators resolve
    /// against. Returns candidates for the user to pick from, so fuzzy
    /// input (titles, partial identifiers) still gets somewhere.
    func searchCandidates(_ query: String, limit: Int = 5) async throws -> [CSLItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var components = URLComponents(string: "https://api.crossref.org/works")!
        components.queryItems = [
            URLQueryItem(name: "query.bibliographic", value: trimmed),
            URLQueryItem(name: "rows", value: String(limit)),
        ]
        guard let url = components.url else {
            throw ResolverError.networkError("Invalid search URL")
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        // Polite-pool etiquette per the Crossref API documentation.
        request.setValue(
            "Write/1.0 (mailto:yuvraj@imaginaryparts.com)",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ResolverError.networkError("The search service returned an error")
        }
        return try Self.parseCrossrefWorks(data)
    }

    static func parseCrossrefWorks(_ data: Data) throws -> [CSLItem] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = root["message"] as? [String: Any],
              let works = message["items"] as? [[String: Any]] else {
            throw ResolverError.decodingError("Unexpected search response")
        }
        return works.compactMap(crossrefWorkToCSL)
    }

    /// Crossref's work schema is CSL-adjacent (titles are arrays, some type
    /// names differ); normalize to proper CSL-JSON.
    private static func crossrefWorkToCSL(_ work: [String: Any]) -> CSLItem? {
        guard let title = (work["title"] as? [String])?.first, !title.isEmpty else { return nil }

        var fields: [String: JSONValue] = ["title": .string(title)]

        let typeMap = [
            "journal-article": "article-journal",
            "proceedings-article": "paper-conference",
            "book-chapter": "chapter",
            "posted-content": "article",
            "monograph": "book",
            "edited-book": "book",
            "reference-book": "book",
        ]
        let rawType = work["type"] as? String ?? "article-journal"
        fields["type"] = .string(typeMap[rawType] ?? rawType)

        if let container = (work["container-title"] as? [String])?.first {
            fields["container-title"] = .string(container)
        }
        if let authors = work["author"] as? [[String: Any]] {
            fields["author"] = .array(authors.map { person in
                var entry: [String: JSONValue] = [:]
                if let family = person["family"] as? String { entry["family"] = .string(family) }
                if let given = person["given"] as? String { entry["given"] = .string(given) }
                if entry.isEmpty, let literal = person["name"] as? String {
                    entry["literal"] = .string(literal)
                }
                return .object(entry)
            })
        }
        for key in ["issued", "published", "published-print", "published-online"] {
            if let issued = work[key], let value = JSONValue(any: issued) {
                fields["issued"] = value
                break
            }
        }
        for (crossrefKey, cslKey) in [
            ("DOI", "DOI"), ("URL", "URL"), ("page", "page"),
            ("volume", "volume"), ("issue", "issue"), ("publisher", "publisher"),
        ] {
            if let value = work[crossrefKey] as? String {
                fields[cslKey] = .string(value)
            }
        }

        // Empty id: ReferenceStore assigns a citekey on add.
        return CSLItem(id: "", fields: fields)
    }
}
