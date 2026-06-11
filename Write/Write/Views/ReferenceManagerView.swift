import SwiftUI

/// Inspector / sheet showing all bibliographic sources for the document.
///
/// Presented as a SwiftUI inspector column on macOS and iPadOS, and as a sheet
/// on iPhone. The view owns no mutable state that outlives it — all mutations
/// go through `viewModel` and the underlying `ReferenceStore`.
struct ReferenceManagerView: View {
    @Bindable var viewModel: EditorViewModel

    // MARK: - Local state

    /// Text typed into the paste / resolve field.
    @State private var pasteInput = ""
    /// True while MetadataResolver is working.
    @State private var isResolving = false
    /// Inline error shown below the paste field on failure.
    @State private var resolveError: String?
    /// Filter text for the source list.
    @State private var filterText = ""
    /// Item selected for editing in ReferenceEditorForm.
    @State private var editingItem: CSLItem?
    /// True when the form is presented for a *new* blank item.
    @State private var isAddingNew = false
    /// Item pending deletion that is currently cited (shows confirmation alert).
    @State private var deletionConfirmation: CSLItem?
    /// ID to flash briefly after a dedupe hit (briefly highlights the row).
    @State private var flashedItemID: String?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            stylePickerHeader
            Divider()
            pasteField
            Divider()
            sourceList
        }
        .sheet(isPresented: $isAddingNew) {
            ReferenceEditorForm(viewModel: viewModel, item: nil)
        }
        .sheet(item: $editingItem) { item in
            ReferenceEditorForm(viewModel: viewModel, item: item)
        }
        .alert(
            "Delete Source",
            isPresented: Binding(
                get: { deletionConfirmation != nil },
                set: { if !$0 { deletionConfirmation = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let item = deletionConfirmation {
                    viewModel.referenceStore.remove(id: item.id)
                }
                deletionConfirmation = nil
            }
            Button("Cancel", role: .cancel) { deletionConfirmation = nil }
        } message: {
            Text("This source is cited in the document. Deleting it will leave its citation chips without a source.")
        }
        .navigationTitle("References")
    }

    // MARK: - Style picker header

    private var stylePickerHeader: some View {
        HStack {
            Text("Style")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Picker("Citation Style", selection: styleBinding) {
                ForEach(CitationEngine.availableStyles, id: \.id) { style in
                    Text(style.name).tag(style.id)
                }
            }
            .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var styleBinding: Binding<String> {
        Binding(
            get: { viewModel.referenceStore.styleID },
            set: { viewModel.setCitationStyle($0) }
        )
    }

    // MARK: - Paste / resolve field

    private var pasteField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TextField("Paste DOI, URL, ISBN, or arXiv…", text: $pasteInput)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    #endif
                    .onSubmit { resolveInput() }

                if isResolving {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 28, height: 28)
                } else {
                    Button {
                        resolveInput()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.borderless)
                    .disabled(pasteInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Resolve and add source")
                }

                Menu {
                    Button("New Source…") { isAddingNew = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("More options")
            }

            if let error = resolveError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func resolveInput() {
        let trimmed = pasteInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let detected = MetadataResolver.detect(trimmed) else {
            resolveError = "Could not detect a DOI, URL, ISBN, or arXiv identifier."
            return
        }
        resolveError = nil
        isResolving = true
        let resolver = MetadataResolver()
        Task {
            do {
                let resolved = try await resolver.resolve(detected)
                await MainActor.run {
                    isResolving = false
                    // Dedupe
                    if let doi = resolved.doi, let existing = viewModel.referenceStore.find(doi: doi) {
                        flashItem(existing.id)
                        pasteInput = ""
                        return
                    }
                    if let url = resolved.url, let existing = viewModel.referenceStore.find(url: url) {
                        flashItem(existing.id)
                        pasteInput = ""
                        return
                    }
                    viewModel.referenceStore.add(resolved)
                    pasteInput = ""
                }
            } catch {
                await MainActor.run {
                    isResolving = false
                    resolveError = (error as? LocalizedError)?.errorDescription
                        ?? "Could not retrieve metadata."
                }
            }
        }
    }

    private func flashItem(_ id: String) {
        flashedItemID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if flashedItemID == id { flashedItemID = nil }
        }
    }

    // MARK: - Source list

    private var filteredItems: [CSLItem] {
        let items = viewModel.referenceStore.items.sorted {
            $0.authorYearSummary.localizedCaseInsensitiveCompare($1.authorYearSummary) == .orderedAscending
        }
        let q = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return items }
        return items.filter {
            $0.authorYearSummary.localizedCaseInsensitiveContains(q) ||
            $0.title.localizedCaseInsensitiveContains(q)
        }
    }

    @ViewBuilder
    private var sourceList: some View {
        VStack(spacing: 0) {
            // Filter field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("Filter", text: $filterText)
                    .font(.callout)
                    #if os(iOS)
                    .autocorrectionDisabled()
                    #endif
                if !filterText.isEmpty {
                    Button { filterText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            let items = filteredItems
            if items.isEmpty {
                ContentUnavailableView(
                    viewModel.referenceStore.items.isEmpty ? "No Sources" : "No Results",
                    systemImage: "books.vertical",
                    description: Text(
                        viewModel.referenceStore.items.isEmpty
                            ? "Paste a DOI, URL, ISBN, or arXiv link above to add a source."
                            : "No sources match \"\(filterText)\"."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(items) { item in
                        SourceRow(
                            item: item,
                            viewModel: viewModel,
                            isFlashed: flashedItemID == item.id
                        )
                        .contextMenu {
                            contextMenuItems(for: item)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                requestDelete(item)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                editingItem = item
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func contextMenuItems(for item: CSLItem) -> some View {
        Button {
            editingItem = item
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        Button {
            #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.id, forType: .string)
            #else
            UIPasteboard.general.string = item.id
            #endif
        } label: {
            Label("Copy Citekey", systemImage: "doc.on.doc")
        }
        Divider()
        Button(role: .destructive) {
            requestDelete(item)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func requestDelete(_ item: CSLItem) {
        let isCited = !(viewModel.citationUsage[item.id]?.isEmpty ?? true)
        if isCited {
            deletionConfirmation = item
        } else {
            viewModel.referenceStore.remove(id: item.id)
        }
    }
}

// MARK: - SourceRow

private struct SourceRow: View {
    let item: CSLItem
    @Bindable var viewModel: EditorViewModel
    var isFlashed: Bool

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.authorYearSummary)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    if !item.title.isEmpty {
                        Text(item.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                usageBadge
            }

            if isExpanded {
                citationLocations
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(isFlashed ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            let usage = viewModel.citationUsage[item.id] ?? []
            if !usage.isEmpty {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }
        }
    }

    // MARK: Usage badge

    @ViewBuilder
    private var usageBadge: some View {
        let count = viewModel.citationUsage[item.id]?.count ?? 0
        if count == 0 {
            Text("uncited")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        } else {
            Text("\(count)×")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        }
    }

    // MARK: Citation locations

    @ViewBuilder
    private var citationLocations: some View {
        let ranges = viewModel.citationUsage[item.id] ?? []
        if !ranges.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(ranges.enumerated()), id: \.offset) { _, range in
                    let excerpt = excerptText(around: range)
                    Button {
                        viewModel.jumpToCitation(at: range)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.right.circle")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(excerpt)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.leading, 4)
        }
    }

    /// Pull ~40 characters of surrounding text around a chip range.
    private func excerptText(around range: NSRange) -> String {
        guard let textStorage = viewModel.textContentStorage.textStorage else { return "…" }
        let nsText = textStorage.string as NSString
        let totalLength = nsText.length
        guard totalLength > 0, range.location < totalLength else { return "…" }

        let contextRadius = 40
        let start = max(0, range.location - contextRadius)
        let end = min(totalLength, NSMaxRange(range) + contextRadius)
        let contextRange = NSRange(location: start, length: end - start)
        var excerpt = nsText.substring(with: contextRange)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)

        if start > 0 { excerpt = "…" + excerpt }
        if end < totalLength { excerpt = excerpt + "…" }
        return excerpt
    }
}
