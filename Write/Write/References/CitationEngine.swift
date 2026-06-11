import Foundation
import JavaScriptCore

// CitationEngine wraps citeproc-js running in a JavaScriptCore context.
// The class and its helpers take the target's default @MainActor isolation
// so they can freely access InlineTraits (which is also @MainActor in this
// target). Callers on a background queue must dispatch to the main actor.

// MARK: - Supporting types

/// A reference to a single source inside an inline citation cluster.
nonisolated struct CitationRef: Hashable, Codable {
    var itemID: String
    /// Locator value, e.g. "31–33". Nil = cite the whole work.
    var locator: String?
    /// CSL locator term. Defaults to "page" whenever locator is set.
    var label: String?
}

/// A fully-formatted bibliography entry ready for display.
struct FormattedEntry {
    /// Plain text (entities decoded, tags stripped).
    var text: String
    /// Italic / bold / super / sub runs over `text`'s UTF-16 code units.
    var traitRuns: [(NSRange, InlineTraits)]
}

// MARK: - Error

nonisolated enum CitationEngineError: Error, CustomStringConvertible {
    case assetNotFound(String)
    case jsException(String)
    case engineSetupFailed(String)

    var description: String {
        switch self {
        case .assetNotFound(let name):  return "CitationEngine: asset not found: \(name)"
        case .jsException(let msg):     return "CitationEngine: JS exception: \(msg)"
        case .engineSetupFailed(let m): return "CitationEngine: setup failed: \(m)"
        }
    }
}

// MARK: - CitationEngine

/// JavaScriptCore wrapper around citeproc-js.
///
/// One engine instance = one style. Swap styles by constructing a new instance.
final class CitationEngine {

    // MARK: - Available styles

    /// Styles bundled with the app, in display order for the style picker.
    static let availableStyles: [(id: String, name: String)] = [
        ("apa",                          "APA 7"),
        ("harvard-cite-them-right",      "Harvard (Cite Them Right)"),
        ("modern-language-association",  "MLA 9"),
        ("chicago-author-date",          "Chicago 18 (Author-Date)"),
        ("ieee",                         "IEEE"),
        ("vancouver",                    "Vancouver"),
    ]

    // MARK: - State

    private let ctx: JSContext
    /// Items keyed by citekey; shared by the JSContext closure and update().
    private let itemsBox: ItemsBox

    // MARK: - Bundle init

    /// Load from the app bundle. CitationAssets files land flat in Resources.
    convenience init(styleID: String, items: [[String: Any]]) throws {
        func bundleURL(_ fileName: String) throws -> URL {
            if let url = Bundle.main.url(forResource: fileName, withExtension: nil) {
                return url
            }
            if let url = Bundle.main.url(forResource: fileName,
                                         withExtension: nil,
                                         subdirectory: "CitationAssets") {
                return url
            }
            throw CitationEngineError.assetNotFound(fileName)
        }

        let citeprocURL = try bundleURL("citeproc.js")
        let styleURL    = try bundleURL("\(styleID).csl")
        let localeTag   = styleID == "harvard-cite-them-right" ? "en-GB" : "en-US"
        let localeURL   = try bundleURL("locales-\(localeTag).xml")

        try self.init(styleID: styleID,
                      citeprocURL: citeprocURL,
                      styleURL: styleURL,
                      localeURL: localeURL,
                      items: items)
    }

    // MARK: - File-URL init (used by CLI test harness without an app bundle)

    init(styleID: String,
         citeprocURL: URL,
         styleURL: URL,
         localeURL: URL,
         items: [[String: Any]]) throws {

        guard let jsc = JSContext() else {
            throw CitationEngineError.engineSetupFailed("JSContext() returned nil")
        }
        self.ctx = jsc

        let box = ItemsBox(items)
        self.itemsBox = box

        // Surface JS exceptions as Swift errors via a throw-on-next-call pattern.
        var pendingException: String? = nil
        jsc.exceptionHandler = { _, val in
            pendingException = val?.toString() ?? "unknown JS exception"
        }
        func throwIfNeeded() throws {
            if let msg = pendingException {
                pendingException = nil
                throw CitationEngineError.jsException(msg)
            }
        }

        // Load citeproc.js
        let citeprocSrc = try String(contentsOf: citeprocURL, encoding: .utf8)
        jsc.evaluateScript(citeprocSrc)
        try throwIfNeeded()

        // Expose style and locale XML as JS globals so the closure-free
        // bootstrap script can read them.
        let styleXML  = try String(contentsOf: styleURL,  encoding: .utf8)
        let localeXML = try String(contentsOf: localeURL, encoding: .utf8)
        jsc.setObject(styleXML,  forKeyedSubscript: "__styleXML"  as NSString)
        jsc.setObject(localeXML, forKeyedSubscript: "__localeXML" as NSString)
        try throwIfNeeded()

        // Install retrieveItem as a Swift block. The block closes over `box`
        // so it always reflects the most recent call to update(items:).
        let retrieve: @convention(block) (String) -> JSValue = { [box] id in
            guard let dict = box.items[id] else { return JSValue(undefinedIn: jsc) }
            return JSValue(object: dict, in: jsc) ?? JSValue(undefinedIn: jsc)
        }
        jsc.setObject(retrieve, forKeyedSubscript: "__retrieveItem" as NSString)

        // Build the sys object and CSL.Engine in JS.
        jsc.evaluateScript("""
        var __sys = {
            retrieveLocale: function(_lang) { return __localeXML; },
            retrieveItem:   function(id)    { return __retrieveItem(id); }
        };
        var __engine = new CSL.Engine(__sys, __styleXML);
        """)
        try throwIfNeeded()

        guard let eng = jsc.objectForKeyedSubscript("__engine"),
              !eng.isNull, !eng.isUndefined else {
            throw CitationEngineError.engineSetupFailed("CSL.Engine produced nil")
        }

        // Register all item IDs with the engine so disambiguation can run.
        jsc.setObject(Array(box.items.keys), forKeyedSubscript: "__ids" as NSString)
        jsc.evaluateScript("__engine.updateItems(__ids);")
        try throwIfNeeded()
    }

    // MARK: - Public API

    /// Replace the full item set (e.g. after adding/removing a source).
    func update(items: [[String: Any]]) {
        itemsBox.replace(items)
        ctx.setObject(Array(itemsBox.items.keys), forKeyedSubscript: "__ids" as NSString)
        ctx.evaluateScript("__engine.updateItems(__ids);")
    }

    /// Format an inline citation cluster, e.g. "(Smith, 2020, p. 31)".
    func inlineCitation(_ refs: [CitationRef]) -> String {
        let rawList: [[String: Any]] = refs.map { ref in
            var entry: [String: Any] = ["id": ref.itemID]
            if let loc = ref.locator, !loc.isEmpty {
                entry["locator"] = loc
                entry["label"]   = ref.label ?? "page"
            }
            return entry
        }
        ctx.setObject(rawList, forKeyedSubscript: "__citeList" as NSString)
        let raw = ctx.evaluateScript("__engine.makeCitationCluster(__citeList);")?.toString() ?? ""
        // citeproc may emit HTML entities (&#38; for &) even in citation clusters;
        // pass through CitationHTML to decode entities and strip any stray markup.
        let (text, _) = CitationHTML.parse(raw)
        return text
    }

    /// Return bibliography entries in style order, with inline-trait markup.
    func bibliography() -> [FormattedEntry] {
        guard let result = ctx.evaluateScript("__engine.makeBibliography();"),
              !result.isNull, !result.isUndefined
        else { return [] }

        // Returns [params, [htmlString, ...]]
        guard let entryArr = result.objectAtIndexedSubscript(1),
              entryArr.isArray
        else { return [] }

        let count = Int(entryArr.objectForKeyedSubscript("length")?.toInt32() ?? 0)
        return (0..<count).compactMap { i in
            let raw = entryArr.objectAtIndexedSubscript(i)?.toString() ?? ""
            let (text, runs) = CitationHTML.parse(raw)
            return FormattedEntry(text: text, traitRuns: runs)
        }
    }
}

// MARK: - ItemsBox

/// Reference-type container so the JSContext retrieveItem closure and the
/// update() method always share the same dictionary.
private final class ItemsBox {
    var items: [String: [String: Any]]

    init(_ list: [[String: Any]]) {
        var d: [String: [String: Any]] = [:]
        for item in list {
            if let id = item["id"] as? String { d[id] = item }
        }
        self.items = d
    }

    func replace(_ list: [[String: Any]]) {
        var d: [String: [String: Any]] = [:]
        for item in list {
            if let id = item["id"] as? String { d[id] = item }
        }
        self.items = d
    }
}
