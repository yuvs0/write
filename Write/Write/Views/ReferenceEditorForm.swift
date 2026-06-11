import SwiftUI

/// Add / edit form for a single bibliographic source.
///
/// When `item` is nil the form creates a new blank source.  When `item` is
/// non-nil the form edits a copy and calls `store.update(_:)` on save.
struct ReferenceEditorForm: View {
    @Bindable var viewModel: EditorViewModel
    /// The item being edited, or nil for a new blank source.
    let item: CSLItem?

    @Environment(\.dismiss) private var dismiss

    // MARK: - Draft state

    @State private var type: String
    @State private var title: String
    @State private var authors: [(family: String, given: String)]
    @State private var year: String
    @State private var containerTitle: String
    @State private var volume: String
    @State private var issue: String
    @State private var pages: String
    @State private var publisher: String
    @State private var doi: String
    @State private var url: String

    // MARK: - Type definitions

    private struct CSLType: Identifiable, Hashable {
        let id: String
        let displayName: String
    }

    private static let cslTypes: [CSLType] = [
        CSLType(id: "article-journal",    displayName: "Journal Article"),
        CSLType(id: "book",               displayName: "Book"),
        CSLType(id: "chapter",            displayName: "Book Chapter"),
        CSLType(id: "paper-conference",   displayName: "Conference Paper"),
        CSLType(id: "webpage",            displayName: "Web Page"),
        CSLType(id: "article-newspaper",  displayName: "News Article"),
        CSLType(id: "report",             displayName: "Report"),
        CSLType(id: "thesis",             displayName: "Thesis"),
    ]

    // MARK: - Init

    init(viewModel: EditorViewModel, item: CSLItem?) {
        self.viewModel = viewModel
        self.item = item

        let src = item ?? CSLItem(id: "", fields: [:])
        _type = State(initialValue: src.type)
        _title = State(initialValue: src.title)

        let auths = src.authors
        _authors = State(initialValue: auths.isEmpty ? [("", "")] : auths)

        _year = State(initialValue: src.issuedYear.map(String.init) ?? "")
        _containerTitle = State(initialValue: src.containerTitle ?? "")
        _volume = State(initialValue: src.fields["volume"]?.stringValue ?? "")
        _issue = State(initialValue: src.fields["issue"]?.stringValue ?? "")
        _pages = State(initialValue: src.fields["page"]?.stringValue ?? "")
        _publisher = State(initialValue: src.fields["publisher"]?.stringValue ?? "")
        _doi = State(initialValue: src.doi ?? "")
        _url = State(initialValue: src.url ?? "")
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                typeSection
                titleSection
                authorsSection
                detailsSection
                identifiersSection

                if let existingItem = item {
                    Section("Citekey") {
                        Text(existingItem.id)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(item == nil ? "New Source" : "Edit Source")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    // MARK: - Sections

    private var typeSection: some View {
        Section("Type") {
            Picker("Source Type", selection: $type) {
                ForEach(Self.cslTypes) { cslType in
                    Text(cslType.displayName).tag(cslType.id)
                }
            }
            .labelsHidden()
            #if os(macOS)
            .pickerStyle(.menu)
            #else
            .pickerStyle(.wheel)
            .frame(height: 120)
            #endif
        }
    }

    private var titleSection: some View {
        Section("Title") {
            TextField("Title", text: $title, axis: .vertical)
                .lineLimit(2...4)
        }
    }

    private var authorsSection: some View {
        Section("Authors") {
            ForEach(Array(authors.indices), id: \.self) { index in
                HStack {
                    TextField("Family name", text: Binding(
                        get: { authors[index].family },
                        set: { authors[index].family = $0 }
                    ))
                    Divider()
                    TextField("Given name", text: Binding(
                        get: { authors[index].given },
                        set: { authors[index].given = $0 }
                    ))
                    Button {
                        authors.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .disabled(authors.count == 1)
                }
            }
            Button {
                authors.append(("", ""))
            } label: {
                Label("Add Author", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            HStack {
                Text("Year")
                    .foregroundStyle(.secondary)
                TextField("Year", text: $year)
                    .multilineTextAlignment(.trailing)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
            }

            if showsContainerTitle {
                HStack {
                    Text(containerTitleLabel)
                        .foregroundStyle(.secondary)
                    TextField(containerTitleLabel, text: $containerTitle)
                        .multilineTextAlignment(.trailing)
                }
            }

            if showsVolume {
                HStack {
                    Text("Volume")
                        .foregroundStyle(.secondary)
                    TextField("Volume", text: $volume)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Issue")
                        .foregroundStyle(.secondary)
                    TextField("Issue", text: $issue)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Pages")
                        .foregroundStyle(.secondary)
                    TextField("e.g. 31–45", text: $pages)
                        .multilineTextAlignment(.trailing)
                }
            }

            if showsPublisher {
                HStack {
                    Text("Publisher")
                        .foregroundStyle(.secondary)
                    TextField("Publisher", text: $publisher)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private var identifiersSection: some View {
        Section("Identifiers") {
            HStack {
                Text("DOI")
                    .foregroundStyle(.secondary)
                TextField("10.xxxx/…", text: $doi)
                    .multilineTextAlignment(.trailing)
                    #if os(iOS)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    #endif
            }
            HStack {
                Text("URL")
                    .foregroundStyle(.secondary)
                TextField("https://…", text: $url)
                    .multilineTextAlignment(.trailing)
                    #if os(iOS)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
            }
        }
    }

    // MARK: - Field visibility per type

    private var showsContainerTitle: Bool {
        ["article-journal", "chapter", "paper-conference",
         "article-newspaper", "webpage"].contains(type)
    }

    private var showsVolume: Bool {
        ["article-journal", "chapter", "paper-conference"].contains(type)
    }

    private var showsPublisher: Bool {
        ["book", "chapter", "report", "thesis"].contains(type)
    }

    private var containerTitleLabel: String {
        switch type {
        case "article-journal":   return "Journal"
        case "chapter":           return "Book"
        case "paper-conference":  return "Conference"
        case "article-newspaper": return "Newspaper"
        case "webpage":           return "Site Name"
        default:                  return "Container"
        }
    }

    // MARK: - Save

    private func save() {
        var draft = item ?? CSLItem(id: "", fields: [:])
        draft.type = type
        draft.title = title.trimmingCharacters(in: .whitespacesAndNewlines)

        let cleanedAuthors = authors.filter {
            !$0.family.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !$0.given.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        draft.authors = cleanedAuthors

        draft.issuedYear = Int(year.trimmingCharacters(in: .whitespaces))

        let ct = containerTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.containerTitle = ct.isEmpty ? nil : ct

        let doiVal = doi.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.doi = doiVal.isEmpty ? nil : doiVal

        let urlVal = url.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.url = urlVal.isEmpty ? nil : urlVal

        let volVal = volume.trimmingCharacters(in: .whitespacesAndNewlines)
        if volVal.isEmpty { draft.fields.removeValue(forKey: "volume") }
        else { draft.fields["volume"] = .string(volVal) }

        let issueVal = issue.trimmingCharacters(in: .whitespacesAndNewlines)
        if issueVal.isEmpty { draft.fields.removeValue(forKey: "issue") }
        else { draft.fields["issue"] = .string(issueVal) }

        let pagesVal = pages.trimmingCharacters(in: .whitespacesAndNewlines)
        if pagesVal.isEmpty { draft.fields.removeValue(forKey: "page") }
        else { draft.fields["page"] = .string(pagesVal) }

        let pubVal = publisher.trimmingCharacters(in: .whitespacesAndNewlines)
        if pubVal.isEmpty { draft.fields.removeValue(forKey: "publisher") }
        else { draft.fields["publisher"] = .string(pubVal) }

        if item != nil {
            viewModel.referenceStore.update(draft)
        } else {
            viewModel.referenceStore.add(draft)
        }

        dismiss()
    }
}
