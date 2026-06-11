# Backlog

## Recently shipped
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
