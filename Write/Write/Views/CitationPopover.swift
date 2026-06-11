import SwiftUI

/// Popover content for editing a citation chip: shows the source summary, lets
/// the user set a locator (page/chapter/section), remove the citation, or close.
///
/// Edits apply through the view model (rewriting the chip's refs JSON,
/// re-rendering its text from the engine, restyling, serializing) — undo-aware.
struct CitationPopover: View {
    @Bindable var viewModel: EditorViewModel
    /// The chip's character range. Captured at presentation; the popover edits
    /// this chip until dismissed.
    let chipRange: NSRange
    /// Called to dismiss the popover.
    var onDismiss: () -> Void

    @State private var label: LocatorLabel
    @State private var locator: String
    /// The full ref list on the chip; we edit the first ref's locator.
    private let refs: [CitationRef]
    private let source: CSLItem?

    enum LocatorLabel: String, CaseIterable, Identifiable {
        case page, chapter, section
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .page: return "Page"
            case .chapter: return "Chapter"
            case .section: return "Section"
            }
        }
        var cslTerm: String { rawValue }
    }

    init(viewModel: EditorViewModel, chipRange: NSRange, onDismiss: @escaping () -> Void) {
        self.viewModel = viewModel
        self.chipRange = chipRange
        self.onDismiss = onDismiss
        let refs = viewModel.citationRefs(at: chipRange) ?? []
        self.refs = refs
        self.source = viewModel.citationSource(at: chipRange)
        let first = refs.first
        _label = State(initialValue: LocatorLabel(rawValue: first?.label ?? "page") ?? .page)
        _locator = State(initialValue: first?.locator ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sourceSummary

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Picker("Locator", selection: $label) {
                    ForEach(LocatorLabel.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                // Edits are applied once on Done/submit. Applying live would
                // re-render the chip and invalidate this popover's anchor range.
                TextField("e.g. 31–33", text: $locator)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        applyEdits()
                        onDismiss()
                    }
                    #if os(iOS)
                    .autocorrectionDisabled()
                    #endif
            }

            Divider()

            HStack {
                Button(role: .destructive) {
                    viewModel.removeCitation(at: chipRange)
                    onDismiss()
                } label: {
                    Label("Remove Citation", systemImage: "trash")
                }
                .buttonStyle(.borderless)

                Spacer()

                Button("Done") {
                    applyEdits()
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    @ViewBuilder
    private var sourceSummary: some View {
        if let source {
            VStack(alignment: .leading, spacing: 2) {
                Text(source.authorYearSummary)
                    .font(.headline)
                if !source.title.isEmpty {
                    Text(source.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        } else {
            // Source missing from the store (shouldn't normally happen).
            Text(refs.first.map { "@\($0.itemID)" } ?? "Citation")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    /// Rewrite the first ref's locator/label and apply to the chip.
    private func applyEdits() {
        guard !refs.isEmpty else { return }
        var updated = refs
        let trimmed = locator.trimmingCharacters(in: .whitespaces)
        var first = updated[0]
        if trimmed.isEmpty {
            first.locator = nil
            first.label = nil
        } else {
            first.locator = trimmed
            first.label = label.cslTerm
        }
        updated[0] = first
        // No-op if nothing actually changed.
        guard updated != refs else { return }
        viewModel.updateCitation(at: chipRange, refs: updated)
    }
}
