import SwiftUI

struct DocumentStatistics {
    var words = 0
    var characters = 0
    var charactersExcludingSpaces = 0
    var sentences = 0
    var paragraphs = 0

    /// Reading time at a typical 220 words per minute.
    var readingMinutes: Int {
        words == 0 ? 0 : max(1, Int((Double(words) / 220).rounded(.up)))
    }

    static func compute(from text: String) -> DocumentStatistics {
        var stats = DocumentStatistics()
        let fullRange = text.startIndex..<text.endIndex

        text.enumerateSubstrings(in: fullRange, options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            stats.words += 1
        }
        text.enumerateSubstrings(in: fullRange, options: [.bySentences, .substringNotRequired]) { _, _, _, _ in
            stats.sentences += 1
        }
        for character in text {
            stats.characters += 1
            if !character.isWhitespace {
                stats.charactersExcludingSpaces += 1
            }
        }
        stats.paragraphs = text
            .components(separatedBy: .newlines)
            .count { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        return stats
    }
}

/// Floating word-count chip (macOS and iPadOS). Tapping it opens the full
/// statistics panel in a popover.
struct StatsChip: View {
    @Bindable var viewModel: EditorViewModel
    @State private var showsPanel = false

    var body: some View {
        let statistics = viewModel.statistics
        Button {
            showsPanel.toggle()
        } label: {
            Text("\(statistics.words) words")
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .popover(isPresented: $showsPanel, arrowEdge: .bottom) {
            StatsPanel(statistics: statistics)
                .presentationCompactAdaptation(.popover)
        }
        .help("Document statistics")
    }
}

struct StatsPanel: View {
    let statistics: DocumentStatistics

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Statistics")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 7) {
                row("Words", statistics.words)
                row("Characters", statistics.characters)
                row("Characters (no spaces)", statistics.charactersExcludingSpaces)
                row("Sentences", statistics.sentences)
                row("Paragraphs", statistics.paragraphs)
                GridRow {
                    Text("Reading time")
                        .foregroundStyle(.secondary)
                    Text(readingTimeText)
                        .monospacedDigit()
                        .gridColumnAlignment(.trailing)
                }
            }
            .font(.callout)
        }
        .padding(16)
        .frame(minWidth: 220, alignment: .leading)
    }

    private var readingTimeText: String {
        statistics.readingMinutes == 0 ? "—" : "\(statistics.readingMinutes) min"
    }

    private func row(_ label: String, _ value: Int) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value.formatted())
                .monospacedDigit()
                .gridColumnAlignment(.trailing)
        }
    }
}
