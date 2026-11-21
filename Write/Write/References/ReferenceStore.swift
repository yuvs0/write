import Foundation
import Observation

// MARK: - ReferenceStore

/// Per-document store for bibliographic sources.
/// Observing `revision` triggers document persistence (onChange in view layer).
@Observable
final class ReferenceStore {

    // MARK: Public state

    private(set) var items: [CSLItem] = []

    var styleID: String {
        get { settings["citationStyle"]?.stringValue ?? "apa" }
        set { settings["citationStyle"] = .string(newValue); revision += 1 }
    }

    /// Bumped on every mutation. The UI layer uses onChange(of: revision) to
    /// push serialized data back into the document.
    private(set) var revision: Int = 0

    // MARK: Private state

    /// Raw settings dictionary — preserves any keys we don't know about.
    private var settings: [String: JSONValue] = [:]

    // MARK: - Init

    init(referencesData: Data? = nil, settingsData: Data? = nil) {
        if let data = referencesData {
            self.items = (try? JSONDecoder().decode([CSLItem].self, from: data)) ?? []
        }

        if let data = settingsData {
            self.settings = (try? JSONDecoder().decode([String: JSONValue].self, from: data)) ?? [:]
        }
    }

    // MARK: - CRUD

    /// Add an item, generating or deduplicating its citekey, and return the stored copy.
    @discardableResult
    func add(_ item: CSLItem) -> CSLItem {
        var stored = item
        stored.id = resolvedCitekey(for: item)
        items.append(stored)
        revision += 1
        return stored
    }

    func update(_ item: CSLItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx] = item
        revision += 1
    }

    func remove(id: String) {
        items.removeAll { $0.id == id }
        revision += 1
    }

    func item(id: String) -> CSLItem? {
        items.first { $0.id == id }
    }

    // MARK: - Dedupe finders

    func find(doi: String) -> CSLItem? {
        let normalized = doi.lowercased()
        return items.first { $0.doi?.lowercased() == normalized }
    }

    func find(url: String) -> CSLItem? {
        let normalized = Self.normalizeURL(url)
        return items.first { item in
            guard let itemURL = item.url else { return false }
            return Self.normalizeURL(itemURL) == normalized
        }
    }

    // MARK: - Serialization

    func referencesData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(items)
    }

    func settingsData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(settings)
    }

    // MARK: - Citekey generation

    /// Returns a unique citekey for the given item, respecting existing ids.
    private func resolvedCitekey(for item: CSLItem) -> String {
        // If the item already has a non-empty, non-colliding id, keep it.
        if !item.id.isEmpty && !items.contains(where: { $0.id == item.id }) {
            return item.id
        }

        // Otherwise generate from author + year (or title word).
        let candidate = baseCitekey(for: item)

        // Check availability
        if !items.contains(where: { $0.id == candidate }) {
            return candidate
        }

        // Collision: append a, b, c, …
        for suffix in "abcdefghijklmnopqrstuvwxyz" {
            let suffixed = candidate + String(suffix)
            if !items.contains(where: { $0.id == suffixed }) {
                return suffixed
            }
        }

        // Extreme fallback
        return UUID().uuidString
    }

    private func baseCitekey(for item: CSLItem) -> String {
        let slug: String
        if let family = item.authors.first?.family, !family.isEmpty {
            slug = Self.asciiSlug(family)
        } else if !item.title.isEmpty {
            let firstWord = String(item.title.split(separator: " ").first ?? Substring(item.title))
            slug = Self.asciiSlug(firstWord)
        } else {
            slug = "source"
        }

        if let year = item.issuedYear {
            return "\(slug)\(year)"
        }
        return slug.isEmpty ? "source" : slug
    }

    // MARK: - Static helpers

    private static func asciiSlug(_ string: String) -> String {
        let stripped = string.applyingTransform(.stripDiacritics, reverse: false) ?? string
        return String(stripped.lowercased().filter { c in
            c.isASCII && (c.isLetter || c.isNumber)
        })
    }

    private static func normalizeURL(_ raw: String) -> String {
        guard var components = URLComponents(string: raw) else {
            return raw.lowercased()
        }
        // Strip fragment
        components.fragment = nil
        // Lowercase host
        components.host = components.host?.lowercased()
        // Strip trailing slash from path (unless path is just "/")
        if components.path.hasSuffix("/") && components.path.count > 1 {
            components.path = String(components.path.dropLast())
        }
        return (components.url?.absoluteString ?? raw).lowercased()
    }
}
