# References & Citations — Implementation Plan

Goal: first-class academic referencing inside Write — insert citations while
writing, pick a style (Harvard, APA, MLA, Chicago, IEEE, Vancouver, …), and
get a correctly formatted bibliography in the editor and in every export
(PDF, DOCX). The user never formats a reference by hand.

## Guiding decisions

1. **Build on CSL (Citation Style Language).** Styles like "Harvard" are not
   one format — there are dozens of institutional variants. CSL is the open
   standard used by Zotero/Mendeley/Pandoc: ~2,000 maintained styles as XML
   files (`citation-style-language/styles` repo, CC-BY-SA). We implement (or
   port) a CSL processor rather than hand-coding each style. Hand-coding
   APA + Harvard "author–date" first is an acceptable v1 shortcut, but the
   data model must be CSL-shaped from day one so styles scale later.
2. **CSL-JSON is the canonical reference model.** Every reference is stored
   as a CSL-JSON item (`type`, `author[]`, `title`, `issued`, `DOI`, …).
   This gives us import/export compatibility with Zotero, BibTeX
   converters, and DOI lookups for free.
3. **References live in the document package.** A `references.json` file
   beside `content.md` keeps each document self-contained and syncable.
   A later iteration can add an app-wide library with per-document links.
4. **Citations in the text are stable keys, not formatted text.** In
   markdown storage we use Pandoc-style cite syntax: `[@smith2020, p. 31]`.
   In the editor the citation is an atomic chip (text attachment / custom
   attribute run) rendered as the *formatted* citation for the active style
   — e.g. "(Smith, 2020, p. 31)" — and is not character-editable; clicking
   it opens the citation editor popover.

## Architecture

```
Document package
├── content.md          ← body text with [@citekey] markers
└── references.json     ← CSL-JSON array, one item per reference

App
├── ReferenceStore        (per-document; loads/saves references.json)
├── CitationParser        (maps [@key] runs ⇄ .writeCitation attribute runs)
├── CSLProcessor          (style XML + items → formatted citations + bibliography)
│     ├── StyleRepository (bundled subset + on-demand download of full repo)
│     └── Locale files    (CSL locales for punctuation/terms)
└── UI
      ├── Citation popover    (search library, insert, edit locator/prefix)
      ├── Reference editor    (form per type: book, article, chapter, web…)
      ├── Bibliography block  (auto-generated, read-only, restyled live)
      └── Style picker        (document setting; persisted in package)
```

### The CSL processor

- v1: implement the subset of CSL needed by the top ~10 styles
  (author-date + numeric + note classes cover almost everything):
  name formatting (initials, et-al rules), date parts, title casing,
  punctuation joins, sorting, disambiguation (2020a/2020b), locators.
- Test against the official CSL test fixtures for the styles we ship.
- Alternative considered: embed citeproc-js in a JSCore context (heavy,
  but battle-tested) — keep as fallback if the native subset proves
  error-prone. Decide after a spike; JSCore is available on all our
  platforms, so this is a realistic shortcut to full style coverage.

### Reference intake (the part users feel)

Priority order:
1. **Paste a DOI / URL / ISBN** → resolve automatically:
   - DOI → `https://doi.org/{doi}` with `Accept: application/vnd.citationstyles.csl+json`
   - ISBN → OpenLibrary / Google Books API → map to CSL-JSON
   - URL → fetch page, read OpenGraph/Highwire meta tags → `webpage` item
2. **Manual form** — per-type fields with validation, author list editor.
3. **Import** — BibTeX (`.bib`) and CSL-JSON file import; Zotero export
   round-trips through both.

### Editor integration

- Typing `@` in the editor (or ⌘⇧C / toolbar "Cite") opens the citation
  popover anchored at the caret: fuzzy-search existing references, or
  paste DOI to add-and-cite in one step.
- A citation run carries `.writeCitation` (citekey + locator + flags) the
  same way links carry `.writeLink`; serialization emits `[@key]` and the
  parser recreates the chip. Styler renders chips from CSLProcessor output,
  so switching document style re-renders every citation instantly.
- Bibliography: a trailing document section regenerated on reference or
  style change; excluded from manual editing (block style `.bibliography`).

### Export mapping

- **PDF**: formatted strings come straight from CSLProcessor — nothing extra.
- **DOCX**: emit citations as plain formatted runs in v1. v2: write Word
  field codes (`w:fldSimple` with Zotero/CSL JSON payload) so citations
  stay live for Zotero-using collaborators.

## Milestones

| # | Deliverable | Notes |
|---|-------------|-------|
| 1 | ReferenceStore + references.json + manual reference editor UI | no formatting yet |
| 2 | Citation chips in editor, `[@key]` round-trip in markdown | uses placeholder "(Author, Year)" format |
| 3 | CSL processor spike: native subset vs citeproc-js via JSCore | decision gate |
| 4 | Harvard (Cite Them Right) + APA 7 end-to-end incl. bibliography | the two requested styles first |
| 5 | DOI/ISBN/URL auto-intake | biggest UX win |
| 6 | MLA 9, Chicago 17 (author-date + notes), IEEE, Vancouver | from CSL repo |
| 7 | BibTeX/CSL-JSON import-export; Pandoc-compatible markdown | interop |
| 8 | DOCX live field codes | collaboration |

## Open questions

- App-wide reference library vs per-document only (start per-document;
  library syncs via iCloud later).
- Footnote-class styles (Chicago notes) need footnote support in the
  editor first — sequence after the footnotes backlog item.
- Style picker placement: document settings popover vs File → Document
  Style… menu. Lean document settings, stored in package metadata.
