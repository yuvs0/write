# References & Citations — FINALIZED implementation plan

Status: approved, in implementation. This document is the working spec —
implementation agents should treat the contracts here as binding and flag
(not silently change) anything that doesn't survive contact with reality.

## Decisions (locked)

1. **CSL-JSON** is the canonical model for every source; stored in
   `references.json` inside the `.write` package.
2. **citeproc-js running in JavaScriptCore** is the formatting engine —
   bundled offline, no network. Bundled styles: APA 7, Harvard (Cite Them
   Right), MLA 9, Chicago 17 author-date, IEEE, Vancouver. Locales: en-US,
   en-GB.
3. **Citation style is per-document**, stored in `settings.json` in the
   package; switching restyles all chips + bibliography live.
4. **Citations are atomic chips** in the editor (rendered formatted text,
   not character-editable; click → popover to edit locator/remove).
   Markdown storage uses Pandoc syntax: `[@smith2020]`,
   `[@smith2020, p. 31]`, `[@a; @b]`.
5. **Metadata resolution is native and tiered** — no external service:
   DOI (doi.org CSL-JSON content negotiation) → arXiv API → ISBN
   (OpenLibrary) → generic URL (Highwire `citation_*` meta tags → JSON-LD
   schema.org → OpenGraph → fallback title/site/accessed). User can always
   edit fields afterwards.
6. **⌘↩ on a URL/DOI token** in the editor turns it into a citation chip
   (resolve → dedupe by DOI/URL → insert chip → optional page-number
   popover).
7. **Reference manager is an inspector panel** (trailing edge, toggleable
   from View menu ⌃⌘4) on macOS and iPadOS: source list with search, add
   via paste-link or manual form, edit, delete (warn if cited), usage
   counts, expandable "cited at…" rows that jump to each citation.
8. **Bibliography**: Format menu → "Insert References List" (at cursor /
   at end). A marked region that auto-regenerates whenever sources, style,
   or citations change. Read-only in the editor.
9. **DOCX export is Word-native**: sources → `customXml` part with
   `b:Sources` (Word bibliography schema), in-text citations → SDT-wrapped
   `CITATION` fields with our formatted text as the field result,
   bibliography → SDT-wrapped `BIBLIOGRAPHY` field. URLs/DOIs preserved in
   source records and hyperlinks. Known/accepted: Word's schema is poorer
   than CSL (lossy mapping); Word re-renders with its own engine on
   refresh.

## Module contracts

### CSLItem (References/CSLItem.swift — exists, owned by orchestrator)

JSON-faithful model: `id` (citekey) + `fields: [String: JSONValue]`
holding raw CSL-JSON. Typed accessors for common fields. Round-trips
arbitrary CSL-JSON without loss. `cslJSONObject: [String: Any]` feeds
citeproc directly.

### CitationEngine (References/CitationEngine.swift)

```swift
struct CitationRef: Hashable, Codable {
    var itemID: String
    var locator: String?      // "31-33"
    var label: String?        // CSL locator term, default "page"
}

final class CitationEngine {
    init(styleID: String, items: [[String: Any]]) throws  // loads bundled style/locale/citeproc
    func update(items: [[String: Any]])
    func inlineCitation(_ refs: [CitationRef]) -> String          // plain text, e.g. "(Smith, 2020, p. 31)"
    func bibliography() -> [FormattedEntry]                       // ordered entries
}

struct FormattedEntry {
    var text: String                       // plain text
    var traitRuns: [(NSRange, InlineTraits)]  // italics etc. mapped from citeproc HTML
}
```

citeproc outputs HTML-ish strings (`<i>`, `<b>`, entities) —
`CitationHTML.swift` converts to plain text + InlineTraits runs.
Bundled assets live in `Write/Write/References/CitationAssets/`
(citeproc.js, *.csl, locales-*.xml) and load via `Bundle.main`.

### MetadataResolver (References/MetadataResolver.swift)

```swift
struct MetadataResolver {
    enum Input { case doi(String), arxiv(String), isbn(String), url(URL) }
    static func detect(_ string: String) -> Input?    // also strips doi.org/arxiv.org URL forms to ids
    func resolve(_ input: Input) async throws -> CSLItem
}
```

### ReferenceStore (References/ReferenceStore.swift)

`@Observable` per-document store: `items: [CSLItem]`, `styleID: String`,
CRUD, `find(doi:)/find(url:)`, citekey generation (authorYear + a/b/c
disambiguation), serialization to/from `Data` for the document package.

### Document package (Model/MarkdownDocument.swift)

Package gains `references.json` + `settings.json`; `fileWrapper(...)`
MUST preserve wrappers it doesn't own (assets/, future files) instead of
rebuilding from scratch. Document struct carries `referencesJSON: Data?`
and `settingsJSON: Data?` alongside `rawText`.

### Editor integration

- `.writeCitation` attribute on chip runs; value = JSON-encoded
  `[CitationRef]`. Chip text = engine's formatted citation. Chips are
  atomic: selection snaps around them, editing inside deletes whole chip.
- Serializer emits `[@key, p. X]`; parser recognizes unescaped `[@…]`
  (our serializer escapes literal `[`, so this is unambiguous in our own
  files) and regenerates chip text from the engine at load.
- Bibliography region markers in markdown:
  `<!-- references:begin -->` … `<!-- references:end -->` with a
  "References" heading + entries inside; parser treats the region as
  generated (re-derived from store at load), serializer re-emits current
  formatted entries so plain markdown readers still see the list.
- Usage tracking: scan storage for `.writeCitation` runs → counts +
  locations for the manager (reuse navigator's scroll-to machinery).

### DOCX mapping

CSL type → b:SourceType: article-journal→JournalArticle, book→Book,
chapter→BookSection, paper-conference→ConferenceProceedings,
webpage→InternetSite, report→Report, thesis→Report, else→Misc.
Authors → `b:Author/b:NameList` persons. Title/Year/Pages/Publisher/
URL/DOI mapped where Word has fields. `customXml/item1.xml` +
`customXml/itemProps1.xml` + content-types + rels entries.

## Phases & ownership (agents must stay inside their files)

- **P1a — CitationEngine + assets** (References/CitationEngine.swift,
  CitationHTML.swift, CitationAssets/)
- **P1b — MetadataResolver** (References/MetadataResolver.swift)
- **P1c — ReferenceStore + package I/O** (References/ReferenceStore.swift,
  Model/MarkdownDocument.swift)
- **P2a — schema + serialization** (Editor/RichTextSchema.swift,
  Parsing/*)
- **P2b — editor chips, ⌘↩, bibliography regen** (Editor/*, Styling/*)
- **P2c — manager inspector + View menu** (Views/*, WriteApp.swift)
- **P3 — DOCX/PDF export** (Export/*)
- **P4 — images** (see IMAGES_PLAN.md)

## Verification expectations

- Each phase builds for macOS AND iOS Simulator with zero new warnings.
- Engine: scratch CLI run formats known fixtures in APA + Harvard
  (single author, two authors, et-al, page locator, year disambiguation)
  and bibliography ordering.
- Resolver: live-network CLI checks against a real DOI, arXiv id, ISBN,
  and a news URL.
- Package I/O: round-trip preserves unknown files in the package.
- DOCX: python-docx structural checks + open in real Word (computer-use)
  to confirm Manage Sources sees the sources.

## Deferred (explicitly out of v1)

- Footnote-class styles (Chicago notes) — needs footnotes first.
- App-wide reference library + iCloud sync (per-document only for now).
- Style search/download from the full CSL repo.
- BibTeX import/export.
