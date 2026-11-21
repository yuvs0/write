import Foundation

// Converts citeproc-js HTML-ish output to plain text + InlineTraits runs.
// citeproc emits a small subset of HTML: <i>, <b>, <sup>, <sub>,
// <span style="font-variant:small-caps;">, entity refs (&amp; &lt; &gt; &#NNN;),
// and <div class="csl-entry"> wrappers. Everything else is stripped.

enum CitationHTML {

    // MARK: - Public entry point

    /// Parse citeproc HTML into plain text + trait runs over UTF-16 offsets.
    static func parse(_ html: String) -> (text: String, traitRuns: [(NSRange, InlineTraits)]) {
        var text = ""
        var runs: [(NSRange, InlineTraits)] = []
        // Active trait stack: each push appends a bit, each pop removes it.
        var traitStack: [InlineTraits] = []

        var current = html.startIndex
        let end = html.endIndex

        func currentTraits() -> InlineTraits {
            traitStack.reduce(InlineTraits(), { $0.union($1) })
        }

        // Pending trait run: (utf16StartOffset, traits).
        var pendingStart: Int? = nil
        var pendingTraits: InlineTraits = []

        // Flush any in-flight trait run up to the current text length.
        func flushRun() {
            guard let start = pendingStart else { return }
            let utf16End = (text as NSString).length
            if utf16End > start && !pendingTraits.isEmpty {
                runs.append((NSRange(location: start, length: utf16End - start), pendingTraits))
            }
            pendingStart = nil
        }

        // Append a plain-text character, tracking trait transitions.
        func appendChar(_ ch: Character) {
            let traits = currentTraits()
            if traits != pendingTraits {
                flushRun()
                if !traits.isEmpty {
                    pendingStart = (text as NSString).length
                    pendingTraits = traits
                }
            } else if !traits.isEmpty && pendingStart == nil {
                pendingStart = (text as NSString).length
                pendingTraits = traits
            }
            text.append(ch)
        }

        func appendString(_ s: String) {
            for ch in s { appendChar(ch) }
        }

        while current < end {
            if html[current] == "<" {
                // Find closing >
                guard let closeAngle = html[current...].firstIndex(of: ">") else {
                    // Malformed — emit rest as text
                    appendString(String(html[current...]))
                    break
                }
                let tagContent = String(html[html.index(after: current)..<closeAngle])
                current = html.index(after: closeAngle)

                let tagLower = tagContent.lowercased().trimmingCharacters(in: .whitespaces)

                if tagLower == "i" || tagLower == "em" {
                    traitStack.append(.italic)
                } else if tagLower == "/i" || tagLower == "/em" {
                    removeFromStack(&traitStack, .italic)
                    flushRun()
                    pendingTraits = currentTraits()
                    pendingStart = pendingTraits.isEmpty ? nil : (text as NSString).length
                } else if tagLower == "b" || tagLower == "strong" {
                    traitStack.append(.bold)
                } else if tagLower == "/b" || tagLower == "/strong" {
                    removeFromStack(&traitStack, .bold)
                    flushRun()
                    pendingTraits = currentTraits()
                    pendingStart = pendingTraits.isEmpty ? nil : (text as NSString).length
                } else if tagLower == "sup" {
                    traitStack.append(.superscript)
                } else if tagLower == "/sup" {
                    removeFromStack(&traitStack, .superscript)
                    flushRun()
                    pendingTraits = currentTraits()
                    pendingStart = pendingTraits.isEmpty ? nil : (text as NSString).length
                } else if tagLower == "sub" {
                    traitStack.append(.subscriptText)
                } else if tagLower == "/sub" {
                    removeFromStack(&traitStack, .subscriptText)
                    flushRun()
                    pendingTraits = currentTraits()
                    pendingStart = pendingTraits.isEmpty ? nil : (text as NSString).length
                } else if tagLower.hasPrefix("span") {
                    // small-caps: map to no trait in v1 (plain)
                    traitStack.append([])
                } else if tagLower == "/span" {
                    if !traitStack.isEmpty { traitStack.removeLast() }
                    flushRun()
                    pendingTraits = currentTraits()
                    pendingStart = pendingTraits.isEmpty ? nil : (text as NSString).length
                }
                // div, /div and any other tags are silently dropped
            } else if html[current] == "&" {
                // Entity reference
                guard let semi = html[current...].firstIndex(of: ";") else {
                    appendChar(html[current])
                    current = html.index(after: current)
                    continue
                }
                let entityRange = html.index(after: current)..<semi
                let entity = String(html[entityRange])
                let decoded = decodeEntity(entity)
                appendString(decoded)
                current = html.index(after: semi)
            } else {
                appendChar(html[current])
                current = html.index(after: current)
            }
        }

        flushRun()

        // Trim leading/trailing whitespace (citeproc HTML wraps entries in
        // indented <div> tags; after stripping the tags the indent and the
        // trailing newline remain as literal whitespace in the plain text).
        let nsText = text as NSString
        let trimRange = (text as NSString).rangeOfCharacter(from: .whitespacesAndNewlines.inverted)
        guard trimRange.location != NSNotFound else { return ("", []) }
        let leadingOffset = trimRange.location
        let trailingEnd   = nsText.rangeOfCharacter(
            from: .whitespacesAndNewlines.inverted,
            options: .backwards
        ).upperBound
        let trimmedText = nsText.substring(with: NSRange(location: leadingOffset,
                                                          length: trailingEnd - leadingOffset)) as String
        // Shift all trait-run locations by -leadingOffset, dropping runs that
        // fall entirely outside the trimmed range.
        let adjustedRuns: [(NSRange, InlineTraits)] = runs.compactMap { (range, traits) in
            let newLoc = range.location - leadingOffset
            let newEnd = min(newLoc + range.length, (trimmedText as NSString).length)
            guard newLoc < (trimmedText as NSString).length, newEnd > newLoc, newLoc >= 0 else {
                return nil
            }
            return (NSRange(location: newLoc, length: newEnd - newLoc), traits)
        }
        return (trimmedText, adjustedRuns)
    }

    // MARK: - Helpers

    private static func removeFromStack(_ stack: inout [InlineTraits], _ trait: InlineTraits) {
        // Remove the last occurrence of the given trait.
        for i in stride(from: stack.count - 1, through: 0, by: -1) {
            if stack[i] == trait {
                stack.remove(at: i)
                return
            }
        }
    }

    private static func decodeEntity(_ entity: String) -> String {
        switch entity {
        case "amp":  return "&"
        case "lt":   return "<"
        case "gt":   return ">"
        case "quot": return "\""
        case "apos": return "'"
        case "nbsp": return "\u{00A0}"
        default:
            if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                // Hexadecimal numeric reference &#xNNNN;
                let hex = String(entity.dropFirst(2))
                if let codePoint = UInt32(hex, radix: 16),
                   let scalar = Unicode.Scalar(codePoint) {
                    return String(scalar)
                }
            } else if entity.hasPrefix("#") {
                // Decimal numeric reference &#NNN;
                let digits = String(entity.dropFirst())
                if let codePoint = UInt32(digits),
                   let scalar = Unicode.Scalar(codePoint) {
                    return String(scalar)
                }
            }
            return "&\(entity);"
        }
    }
}
