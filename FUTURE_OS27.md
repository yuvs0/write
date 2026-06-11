# OS 27 / Xcode 27 — adoption notes

WWDC 2026 (June 8–12, 2026) introduced iOS 27, iPadOS 27, and macOS 27
"Golden Gate". The app currently targets the 26.x SDKs; everything below is
deferred until the project moves to Xcode 27. Verify exact API signatures
against the Xcode 27 beta docs before adopting — names below were taken from
session pages, not compiled against.

## High value for Write

1. **New SwiftUI document model — replace `FileDocument`**
   `ReadableDocument` / `WritableDocument` protocols: `@Observable` document
   classes, async `snapshot(contentType:)`, `DocumentWriter` with
   incremental background writes and snapshot diffing (`previous:`).
   - Fixes today's design tension: we serialize the whole markdown string on
     every keystroke so SwiftUI's value-type document stays current. With an
     observable document + async snapshots, serialization moves off the hot
     path. This is the single biggest architectural win.
   - `DocumentWriter` supports multiple `writableContentTypes` — could make
     PDF/DOCX export a first-class save-as path rather than a custom
     `fileExporter` flow.
   - `DocumentCreationSource` + `NewDocumentButton` in
     `DocumentGroupLaunchScene` — richer "new document" launch experience
     (e.g. "New from template").
   - Session: WWDC26 #269 "What's new in SwiftUI".

2. **TextKit improvements — session #370 "Elevate your app's text experience"**
   - `NSTextView`/`UITextView` now publicly conform to
     `NSTextViewportLayoutControllerDelegate`: subclass and override
     `textViewportLayoutController(_:configureRenderingSurfaceFor:)` to
     decorate paragraphs. Use for: quote bars, code-block backgrounds with
     rounded corners, focus-mode dimming — things we currently approximate
     with plain attributes.
   - `NSTextViewportRenderingSurface` cacheable per-fragment rendering
     surfaces — likely helps scroll performance on huge documents.
   - Attachment view-provider reuse policies
     (`.onEditingInlineParagraphs`, `.onScrollingOutOfViewport`) — relevant
     when we add inline images and citation chips (see REFERENCES_PLAN.md).

3. **iPadOS 27 persistent menu bar**
   Users can keep the menu bar always visible on iPad. Our `Commands`
   (Format / Export / Zoom) are already in place, so we get this for free —
   but audit menu completeness on iPad once on the 27 SDK.
   "Modernize your UIKit app" (#278) lists new requirements for menus.

4. **Liquid Glass refinements (automatic + one breaking change)**
   Recompiling with Xcode 27 force-adopts Liquid Glass — the opt-out is
   removed. Audit the custom `glassEffect` capsule toolbar and the
   `NSVisualEffectView` background under the new appearance.
   New toolbar APIs worth adopting: `visibilityPriority(.high)`,
   `ToolbarOverflowMenu`, `toolbarMinimizeBehavior(.onScrollDown)` (nice for
   distraction-free writing — toolbar tucks away while you write).
   `@Environment(\.appearsActive)` to dim inactive-window chrome.

5. **Apple Intelligence / Foundation Models**
   - System proofreading happens automatically in most text views on 27 —
     test interaction with our custom attribute pipeline.
   - `LanguageModel` protocol + Dynamic Profiles: a "rewrite/summarize
     selection" writing tool could ship on-device with provider choice.
   - New Evaluations framework for testing AI features.
   - Sessions: #241, #242, #319.

6. **PencilKit handwriting recognition + PaperKit**
   Handwriting-to-text beyond drawing canvases (same engine as Notes).
   Candidate: scribble-anywhere input on iPad.

## Breaking / migration watch-list

- **`@State` becomes a macro** (lazy class init) — source-breaking in some
  patterns; see Apple technote TN3211. We initialize
  `@State EditorViewModel` in `DocumentEditorView.init` — re-test that path.
- `ViewBuilder` → `ContentBuilder` evolution (build-time wins; should be
  transparent).
- Xcode 27 is Apple-silicon-only and bundles agent skills incl.
  "swiftui-whats-new-27" — useful when migrating.

## Explicitly checked, nothing new in 27

- No new TextEditor/AttributedString rich-text APIs (iOS 26's
  `TextEditor(text: Binding<AttributedString>)` remains the state of the
  art; our TextKit 2 approach stays the right call for custom attributes).
- No PDFKit / printing / DOCX export news — keep our exporters.
- No new SwiftUI Settings-scene or hover/pointer APIs.
