import Foundation

enum MarkdownNode {
    case heading(level: Int, content: [InlineNode], range: NSRange)
    case paragraph(content: [InlineNode], range: NSRange)
    case blockquote(content: [InlineNode], range: NSRange)
    case codeBlock(language: String?, text: String, range: NSRange)
    case listItem(ordered: Bool, content: [InlineNode], range: NSRange)
    case thematicBreak(range: NSRange)
}

enum InlineNode {
    case text(String, range: NSRange)
    case strong(children: [InlineNode], range: NSRange)
    case emphasis(children: [InlineNode], range: NSRange)
    case strikethrough(children: [InlineNode], range: NSRange)
    case inlineCode(String, range: NSRange)
    case link(destination: String?, children: [InlineNode], range: NSRange)
}
