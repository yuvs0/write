#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Foundation

/// Owns the citation-specific machinery for the editor: the live citeproc
/// engine, chip re-rendering, bibliography regeneration, and the geometry +
/// token-detection helpers the platform views need.
///
/// The view model keeps a `CitationController` and forwards to it. The pure
/// model transforms (re-render chips, regenerate the bibliography region) are
/// `static` functions over a plain `NSMutableAttributedString`, so they can be
/// exercised headlessly without a text view — see the scratch harness.
final class CitationController {

    /// The store backing this document. Owned by the view model; the
    /// controller reads `items`/`styleID` and never mutates it.
    let store: ReferenceStore

    /// Lazily-created engine. `nil` once a build attempt has failed so we
    /// don't retry on every keystroke. Chips fall back to placeholder text
    /// whenever the engine is unavailable — never a crash.
    private(set) var engine: CitationEngine?
    private var engineStyleID: String?
    private var engineFailed = false

    init(store: ReferenceStore) {
        self.store = store
    }

    // MARK: - Engine lifecycle

    /// Return a usable engine reflecting the current style + items, building or
    /// rebuilding it as needed. Returns nil if the engine cannot be created
    /// (missing assets, JS failure) — callers degrade gracefully.
    @discardableResult
    func currentEngine() -> CitationEngine? {
        let styleID = store.styleID
        if let engine, engineStyleID == styleID {
            engine.update(items: store.items.map(\.cslJSONObject))
            return engine
        }
        guard !engineFailed || engineStyleID != styleID else { return nil }

        do {
            let built = try CitationEngine(
                styleID: styleID,
                items: store.items.map(\.cslJSONObject)
            )
            engine = built
            engineStyleID = styleID
            engineFailed = false
            return built
        } catch {
            // Degrade gracefully: keep placeholders, remember the failure so
            // we don't thrash trying to rebuild every keystroke.
            engine = nil
            engineStyleID = styleID
            engineFailed = true
            return nil
        }
    }

    // MARK: - Pure model transforms (nonisolated, headlessly testable)

    /// Locations of every `.writeCitation` run in `storage`, front-to-back,
    /// each paired with its decoded refs and JSON value.
    static func chipRuns(
        in storage: NSAttributedString
    ) -> [(range: NSRange, refs: [CitationRef], json: String)] {
        var result: [(NSRange, [CitationRef], String)] = []
        let text = storage.string as NSString
        let full = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(.writeCitation, in: full, options: []) { value, range, _ in
            guard let json = value as? String,
                  let refs = json.decodedCitationRefs() else { return }
            // Defensive: never let a chip run swallow paragraph breaks —
            // replacing a newline-bearing run would merge paragraphs.
            var trimmed = range
            while trimmed.length > 0,
                  text.character(at: NSMaxRange(trimmed) - 1) == 0x0A {
                trimmed.length -= 1
            }
            guard trimmed.length > 0 else { return }
            result.append((trimmed, refs, json))
        }
        return result
    }

    /// Re-render the display text of every chip run from `engine`, walking
    /// back-to-front so earlier ranges stay valid as later runs change length.
    /// Each chip's attributes (incl. `.writeCitation`) are preserved; only the
    /// characters change. Returns true if any chip's text actually changed.
    ///
    /// When `engine` is nil this is a no-op (placeholders stay put).
    @discardableResult
    static func rerenderChips(
        in storage: NSMutableAttributedString,
        engine: CitationEngine?
    ) -> Bool {
        guard let engine else { return false }
        let runs = chipRuns(in: storage)
        guard !runs.isEmpty else { return false }

        var changed = false
        // Back-to-front: mutating a later range never shifts an earlier one.
        for run in runs.reversed() {
            let rendered = engine.inlineCitation(run.refs)
            guard !rendered.isEmpty else { continue }
            let existing = (storage.string as NSString).substring(with: run.range)
            guard existing != rendered else { continue }

            // Preserve the run's attributes; swap only the characters.
            let attrs = storage.attributes(at: run.range.location, effectiveRange: nil)
            let replacement = NSAttributedString(string: rendered, attributes: attrs)
            storage.replaceCharacters(in: run.range, with: replacement)
            changed = true
        }
        return changed
    }

    /// Range of the contiguous bibliography region (every paragraph carrying
    /// `.writeBibliography`), or nil if the document has none. The region is
    /// always contiguous by construction.
    static func bibliographyRange(in storage: NSAttributedString) -> NSRange? {
        let full = NSRange(location: 0, length: storage.length)
        var found: NSRange?
        storage.enumerateAttribute(.writeBibliography, in: full, options: []) { value, range, _ in
            guard (value as? NSNumber)?.boolValue == true else { return }
            found = found.map { NSUnionRange($0, range) } ?? range
        }
        return found
    }

    /// Build a fresh bibliography region as an attributed string: a heading2
    /// "References" paragraph followed by one body paragraph per entry, every
    /// character carrying `.writeBibliography` and entries carrying their
    /// `.writeInlineTraits` runs. Paragraphs are newline-separated; there is no
    /// trailing newline (the caller stitches it into the document). Separating
    /// newlines are re-tagged by `fixBibliographyNewlines` so each terminates
    /// the paragraph to its left.
    static func makeBibliographyRegion(
        entries: [FormattedEntry]
    ) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()

        func bibAttrs(_ block: BlockStyle) -> [NSAttributedString.Key: Any] {
            [.writeBlockStyle: block.rawValue, .writeBibliography: NSNumber(true)]
        }

        // Heading.
        result.append(NSAttributedString(string: "References", attributes: bibAttrs(.heading2)))

        for entry in entries {
            result.append(NSAttributedString(string: "\n", attributes: bibAttrs(.body)))
            let paragraph = NSMutableAttributedString(
                string: entry.text, attributes: bibAttrs(.body)
            )
            for (range, traits) in entry.traitRuns where !traits.isEmpty {
                guard NSMaxRange(range) <= paragraph.length else { continue }
                paragraph.addAttribute(
                    .writeInlineTraits, value: NSNumber(value: traits.rawValue), range: range
                )
            }
            result.append(paragraph)
        }

        fixBibliographyNewlines(result)
        return result
    }

    /// Replace the existing bibliography region in-place (preserving the blank
    /// separator paragraph before it), or build the document fragment to insert.
    /// Returns the assembled region (heading + entries) ready to splice in.
    ///
    /// This is the core regenerate transform used by both the live path and the
    /// headless test. It mutates `storage` directly.
    ///
    /// Behavior:
    /// - If a region exists, its character range is replaced with a freshly
    ///   rendered region (same heading + new entries).
    /// - If no region exists and `engine` is nil, nothing happens.
    @discardableResult
    static func regenerateBibliography(
        in storage: NSMutableAttributedString,
        engine: CitationEngine?
    ) -> Bool {
        guard let engine else { return false }
        guard let region = bibliographyRange(in: storage) else { return false }

        let entries = engine.bibliography()
        let fresh = makeBibliographyRegion(entries: entries)

        // Replace in place. The region range covers whole paragraphs including
        // their trailing newlines except possibly the last paragraph's newline
        // (if the region is at document end). Preserve a trailing newline if the
        // old region had one.
        let nsString = storage.string as NSString
        let hadTrailingNewline = NSMaxRange(region) > 0
            && NSMaxRange(region) <= nsString.length
            && nsString.character(at: NSMaxRange(region) - 1) == 0x0A

        let replacement = NSMutableAttributedString(attributedString: fresh)
        if hadTrailingNewline {
            // Keep the region paragraph-terminated.
            let lastAttrs = replacement.length > 0
                ? replacement.attributes(at: replacement.length - 1, effectiveRange: nil)
                : [.writeBlockStyle: BlockStyle.body.rawValue, .writeBibliography: NSNumber(true)]
            replacement.append(NSAttributedString(string: "\n", attributes: lastAttrs))
        }
        storage.replaceCharacters(in: region, with: replacement)
        return true
    }

    /// Newlines inside a generated region need block-style attributes matching
    /// the paragraph they terminate so the serializer and styler treat them
    /// correctly. `makeBibliographyRegion` writes each separating newline with
    /// heading attrs; re-tag each newline with the *preceding* paragraph's
    /// block style.
    static func fixBibliographyNewlines(_ region: NSMutableAttributedString) {
        let text = region.string as NSString
        for i in 0..<text.length where text.character(at: i) == 0x0A {
            // The newline terminates the paragraph to its left; copy that
            // character's block style onto the newline (keeping bibliography).
            let sourceIndex = i > 0 ? i - 1 : i
            let block = region.blockStyle(at: sourceIndex)
            region.addAttribute(.writeBlockStyle, value: block.rawValue,
                                range: NSRange(location: i, length: 1))
            region.addAttribute(.writeBibliography, value: NSNumber(true),
                                range: NSRange(location: i, length: 1))
            // A newline never carries inline traits.
            region.removeAttribute(.writeInlineTraits, range: NSRange(location: i, length: 1))
        }
    }

    // MARK: - Chip boundary geometry (nonisolated, testable)

    /// If `location` falls strictly inside a chip run (not at either boundary),
    /// return that run's range; otherwise nil.
    static func chipRange(
        containingInterior location: Int, in storage: NSAttributedString
    ) -> NSRange? {
        guard location > 0, location < storage.length else { return nil }
        // A position is "strictly inside" a chip if both the char before and
        // the char at `location` carry the same chip attribute value.
        guard let before = storage.attribute(.writeCitation, at: location - 1, effectiveRange: nil) as? String,
              let after = storage.attribute(.writeCitation, at: location, effectiveRange: nil) as? String,
              before == after else { return nil }
        var effective = NSRange(location: 0, length: 0)
        storage.attribute(.writeCitation, at: location, longestEffectiveRange: &effective,
                          in: NSRange(location: 0, length: storage.length))
        return effective
    }

    /// Snap a single range so neither endpoint sits strictly inside a chip.
    ///
    /// For a zero-length caret that landed inside a chip (e.g. an arrow key
    /// stepping in), snap to the *nearer* boundary so arrowing across a chip
    /// reaches the far side rather than sticking at the near edge. For a
    /// selection, the start snaps to the chip start and the end to the chip end
    /// so the whole chip is enclosed.
    static func snapOutOfChips(
        _ range: NSRange, in storage: NSAttributedString
    ) -> NSRange {
        if range.length == 0, let chip = chipRange(containingInterior: range.location, in: storage) {
            let distToStart = range.location - chip.location
            let distToEnd = NSMaxRange(chip) - range.location
            let snapped = distToEnd <= distToStart ? NSMaxRange(chip) : chip.location
            return NSRange(location: snapped, length: 0)
        }

        var start = range.location
        var end = NSMaxRange(range)
        if let chip = chipRange(containingInterior: start, in: storage) {
            start = chip.location
        }
        if let chip = chipRange(containingInterior: end, in: storage) {
            end = NSMaxRange(chip)
        }
        return NSRange(location: start, length: max(0, end - start))
    }

    /// Expand an edit range so it fully covers any chip runs it partially
    /// intersects. A caret (zero length) immediately *after* a chip expands
    /// backwards to swallow the whole chip (backspace-deletes-chip).
    ///
    /// `isBackspace` distinguishes a backspace (caret after chip → delete chip)
    /// from a forward delete (caret before chip → delete chip).
    static func expandToCoverChips(
        _ range: NSRange, in storage: NSAttributedString, isDeletion: Bool
    ) -> NSRange {
        var start = range.location
        var end = NSMaxRange(range)

        if range.length == 0, isDeletion {
            // Caret deletion: a backspace removes the chip ending at `start`;
            // a forward delete removes the chip starting at `start`.
            if start > 0,
               let chip = chipRange(at: start - 1, in: storage),
               NSMaxRange(chip) == start {
                return chip
            }
            if start < storage.length,
               let chip = chipRange(at: start, in: storage),
               chip.location == start {
                return chip
            }
            return range
        }

        // Non-empty: widen each endpoint that lands inside a chip.
        if start < storage.length, let chip = chipRange(at: start, in: storage),
           chip.location < start {
            start = chip.location
        }
        if end > 0, end <= storage.length, let chip = chipRange(at: end - 1, in: storage),
           NSMaxRange(chip) > end {
            end = NSMaxRange(chip)
        }
        return NSRange(location: start, length: max(0, end - start))
    }

    /// The chip run covering `location` (the character at `location`), or nil.
    static func chipRange(at location: Int, in storage: NSAttributedString) -> NSRange? {
        guard location >= 0, location < storage.length,
              storage.attribute(.writeCitation, at: location, effectiveRange: nil) is String
        else { return nil }
        var effective = NSRange(location: 0, length: 0)
        storage.attribute(.writeCitation, at: location, longestEffectiveRange: &effective,
                          in: NSRange(location: 0, length: storage.length))
        return effective
    }

    /// True if the caret at `location` abuts a chip on either side (so typing
    /// there must not inherit the citation attribute).
    static func caretAbutsChip(_ location: Int, in storage: NSAttributedString) -> Bool {
        if location > 0,
           storage.attribute(.writeCitation, at: location - 1, effectiveRange: nil) is String {
            return true
        }
        if location < storage.length,
           storage.attribute(.writeCitation, at: location, effectiveRange: nil) is String {
            return true
        }
        return false
    }

    /// True if the caret at `location` abuts the bibliography region (so typing
    /// there must not inherit the `.writeBibliography` attribute).
    static func caretAbutsBibliography(_ location: Int, in storage: NSAttributedString) -> Bool {
        func isBib(_ i: Int) -> Bool {
            (storage.attribute(.writeBibliography, at: i, effectiveRange: nil) as? NSNumber)?.boolValue == true
        }
        if location > 0, isBib(location - 1) { return true }
        if location < storage.length, isBib(location) { return true }
        return false
    }

    /// Whether an edit range may proceed given the read-only bibliography
    /// region. An edit is rejected when it *intersects but does not fully
    /// cover* the region (so select-all-region + delete is still allowed).
    static func editAllowedAgainstBibliography(
        _ range: NSRange, in storage: NSAttributedString
    ) -> Bool {
        guard let region = bibliographyRange(in: storage) else { return true }
        let intersection = NSIntersectionRange(range, region)
        if intersection.length == 0 {
            // No overlap. But a zero-length caret edit sitting *inside* the
            // region (typing in the middle) must still be blocked.
            if range.length == 0, range.location > region.location,
               range.location < NSMaxRange(region) {
                return false
            }
            return true
        }
        // Overlaps: allow only if the edit fully covers the region.
        return range.location <= region.location && NSMaxRange(range) >= NSMaxRange(region)
    }

    // MARK: - Token detection for ⌘↩

    /// A detected citable token in a paragraph: its character range (document
    /// coordinates) and the resolver input it maps to.
    struct DetectedToken {
        var range: NSRange
        var text: String
        var input: MetadataResolver.Input
    }

    /// Scan `paragraphText` (covering document range `paragraphRange`) for a
    /// URL/DOI/arXiv/ISBN token whose range contains or abuts `caret`. Prefer a
    /// token that contains the caret, then one ending at the caret, then the
    /// nearest preceding token in the paragraph.
    static func detectToken(
        inParagraph paragraphText: String,
        paragraphRange: NSRange,
        caret: Int
    ) -> DetectedToken? {
        // Tokenize on whitespace, tracking each token's document range.
        let ns = paragraphText as NSString
        var tokens: [(range: NSRange, text: String)] = []
        var idx = 0
        while idx < ns.length {
            // Skip whitespace.
            while idx < ns.length, isWhitespace(ns.character(at: idx)) { idx += 1 }
            guard idx < ns.length else { break }
            let start = idx
            while idx < ns.length, !isWhitespace(ns.character(at: idx)) { idx += 1 }
            let tokenRange = NSRange(location: paragraphRange.location + start, length: idx - start)
            tokens.append((tokenRange, ns.substring(with: NSRange(location: start, length: idx - start))))
        }

        // Build candidates with detected inputs.
        let candidates: [DetectedToken] = tokens.compactMap { token in
            guard let input = MetadataResolver.detect(token.text) else { return nil }
            return DetectedToken(range: token.range, text: token.text, input: input)
        }
        guard !candidates.isEmpty else { return nil }

        // 1. Token containing the caret strictly.
        if let hit = candidates.first(where: {
            caret > $0.range.location && caret < NSMaxRange($0.range)
        }) { return hit }
        // 2. Token ending exactly at the caret (caret just after the token).
        if let hit = candidates.last(where: { NSMaxRange($0.range) == caret }) { return hit }
        // 3. Token starting exactly at the caret.
        if let hit = candidates.first(where: { $0.range.location == caret }) { return hit }
        // 4. Nearest token ending before the caret.
        let preceding = candidates.filter { NSMaxRange($0.range) <= caret }
        if let hit = preceding.max(by: { NSMaxRange($0.range) < NSMaxRange($1.range) }) {
            return hit
        }
        // 5. Otherwise the first token after the caret.
        return candidates.first(where: { $0.range.location >= caret })
    }

    private static func isWhitespace(_ c: unichar) -> Bool {
        c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x2028 || c == 0x00A0
    }
}
