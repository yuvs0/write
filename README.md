# write

A text editor for focused writing sessions. Powerful but simple: no syntax,
no clutter — just prose, with formatting a hover or shortcut away.

## How it works

The editor is true WYSIWYG. Markdown is purely the storage format inside the
`.write` package (`content.md`) — the user never sees or types syntax:

- **Typing `*asterisks*` or `# hashes` keeps them visible as literal text.**
  They are backslash-escaped in storage so they round-trip exactly.
- Formatting comes from the toolbar, the Format menu (⌘B, ⌘I, …), the
  iPhone keyboard accessory bar, or the Notion-style paragraph handle that
  fades in to the left of the hovered paragraph (macOS + iPad pointer).
- Block styles (Title, Heading, Subheading, Body, lists, Quote, Code) and
  inline traits (bold, italic, underline, strikethrough, code, super/subscript)
  are stored as semantic attributes on the text and serialized to markdown.

## Architecture

```
content.md  ──MarkdownToRichText──▶  NSTextStorage with semantic attributes
                                      (.writeBlockStyle, .writeInlineTraits)
            ◀──RichTextToMarkdown──   │
                                      ▼
                       RichTextStyler resolves visual attributes
                       (fonts, spacing, list markers) from the user's
                       StyleConfiguration — editable in Settings
```

- `Write/Write/Parsing` — markdown ⇄ semantic attributed string (swift-markdown)
- `Write/Write/Styling` — style configuration, store, and styler
- `Write/Write/Editor` — view model + TextKit 2 editors per platform
- `Write/Write/Export` — paginated PDF and native-styles DOCX exporters
- `Write/Write/Settings` — per-style font/spacing customization UI

## Export

File → Export as PDF… / Export as Word… (macOS and iPad menu bar).
Headings map to native Word heading styles; lists, quotes, and code carry
through. PDF pagination follows the user's configured styles.

## Plans

- [REFERENCES_PLAN.md](REFERENCES_PLAN.md) — Harvard/APA/MLA/… citation editor
- [FUTURE_OS27.md](FUTURE_OS27.md) — OS 27 / Xcode 27 adoption notes
- [backlog.md](backlog.md) — everything else
