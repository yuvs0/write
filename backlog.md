# Backlog

## Recently shipped (references & images release)
- Reference manager inspector (⌃⌘4): paste DOI/URL/ISBN/arXiv to add sources,
  Crossref bibliographic search fallback with pickable candidates, usage
  badges, cited-at jump rows, per-document citation style (citeproc-js:
  APA/Harvard/MLA/Chicago/IEEE/Vancouver)
- Citation chips: ⌘↩ converts a link at the caret into a live citation,
  click to edit page/chapter/section locator, atomic editing, undo-safe
- Auto-regenerating references list (Format menu, at cursor or end)
- Word-native DOCX export: b:Sources, CITATION/BIBLIOGRAPHY fields,
  hyperlinks — Word's Manage Sources reads the document directly
- Images: originals stored byte-for-byte in the package (never recompressed),
  drag/drop/paste/Insert-menu/photo picker, captions with optional figure
  numbering (computed in exports; DOCX uses native SEQ fields)
- iPad layout fixes: single navigation bar, floating sidebar toggle,
  menu-bar Text Styles, iPhone-only keyboard accessory bar

## Previously shipped
- WYSIWYG editing: markdown is storage-only; typed `*`/`#`/`` ` `` stay
  visible and formatting comes from the toolbar/menu/handle
- Notion-style paragraph handle (hover, macOS + iPad pointer) for block styles
- Formatting toolbar with active states; iPhone/iPad keyboard accessory bar
- Format menu with shortcuts (⌘B/I/U, ⌥⌘1-3, list/quote/code styles)
- Style customisation UI (font, weight, size, italic, spacing per element) —
  macOS Settings window and iOS sheet, applies live to open documents
- Export to PDF and DOCX (File menu on macOS / iPad menu bar; not on iPhone)
- Smart quotes/dashes and spell checking enabled (safe now that the editor
  holds prose, not syntax)
- Centered text column with comfortable margins

## Editor
- Autocorrect: grammar and punctuation (spelling now enabled)
- Image embedding and inline preview
- Table editing with column/row controls
- SVG graphic embedding and preview
- Footnotes and endnotes
- Figure/diagram captions (mapped to docx native captions and figure numbers)
- Cross-references (figures, headings, footnotes)
- Find and replace
- Word count and reading time
- Focus mode (dim non-active paragraph)
- Typewriter scrolling (keep cursor vertically centred)
- Type `@` to cite — see REFERENCES_PLAN.md

## Import
- Import .md files
- Import .docx (Word)

## Export
- DOCX: captions and figure numbers (styles/lists/headings done)
- Export to Google Docs
- Export to Pages
- Export to HTML
- Export on iPhone (share sheet instead of menu bar)

## References
- Harvard/APA/MLA/Chicago/IEEE citation editor — plan in REFERENCES_PLAN.md

## Autosave Recovery
- UI for accepting/rejecting autosave changes on open (when autosave.md differs from content.md)
- Version history browser (show previous saves)

## Style Preferences
- Configure bold/italic to render with alternative font (model supports it;
  needs settings UI)
- Custom paragraph spacing presets
- Line height configuration
- Theme presets (collections of style configurations)
- Import/export style configurations

## Platform
- visionOS support
- Keyboard shortcut customisation
- Sidebar with document outline (heading navigation)
- Split view for viewing two documents side by side (macOS/iPadOS)
- Quick Open (⌘O recent file search)
- Drag and drop file reordering in recents
- Xcode 27 / OS 27 adoption — see FUTURE_OS27.md

## Collaboration
- Share sheet integration
- Handoff between devices (continue editing where you left off)
