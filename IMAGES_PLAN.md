# Images — FINALIZED implementation plan

Status: approved, implementation follows the references feature (P4).

## Decisions (locked)

1. **Originals are sacred**: image files are copied byte-for-byte into an
   `assets/` folder inside the `.write` package and never recompressed or
   resized. Display scaling happens only at render time.
2. Markdown representation is standard:
   `![caption](assets/<shortid>.<ext>)` as its own paragraph. The optional
   title field carries flags: `![caption](assets/x.jpeg "figure")` marks a
   numbered figure.
3. **Caption is the alt text** (single source of truth). The editor
   renders the caption beneath the image inside the attachment cell
   (read-only display); editing happens via a popover on the figure
   (click image → caption field + "numbered figure" toggle + remove).
4. **Figure numbers are never stored** — computed from document order.
   v1 shows numbers only in exports (PDF text, DOCX native Caption style +
   `SEQ Figure` fields so Word numbering/cross-refs work). The editor
   shows just the caption.
5. Insertion: drag & drop, paste, Insert menu (macOS open panel / iOS
   photo picker). HEIC stays HEIC in the package; export transcodes
   losslessly (PNG) only where the target can't read it (DOCX).
6. Unused assets are pruned on save only when no longer referenced by
   content.md and not reachable through undo; when in doubt, keep.

## Architecture

- `Model/MarkdownDocument.swift`: package read/write keeps `assets/`
  wrapper intact (P1c lands the preserve-unknown-wrappers behavior);
  add API to add/fetch asset data by filename.
- `.writeImage` attribute on the attachment character; value = JSON
  (asset filename, caption, isNumberedFigure). The NSTextAttachment
  subclass draws the scaled image + caption line; an
  NSTextAttachmentViewProvider variant can come later for selection
  affordances.
- Parser/serializer: image paragraphs ⇄ attachment runs; alt text
  escaping rules match the existing inline escaping.
- Exporters: PDF draws decoded images (Flate, lossless) with caption +
  computed number below; DOCX embeds original bytes in `word/media/`,
  emits `w:drawing` inline images sized to page width, caption paragraph
  with Caption style + `SEQ Figure \* ARABIC` field.
- Editors: drag/drop + paste interception on both platforms; Insert
  menu command (macOS/iPadOS), photo picker sheet (iOS).

## Verification

- Round-trip: insert → save → reopen keeps identical asset bytes
  (checksum) and caption/figure flags.
- DOCX: python-docx confirms media part + caption SEQ field; visual check
  in Word.
- PDF: image renders, caption shows "Figure N — caption".
