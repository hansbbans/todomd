import SwiftUI

enum MarkdownBodyRenderer {
    static func renderedText(from taskBody: String) throws -> AttributedString {
        let markdown = displayMarkdown(from: taskBody)
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return AttributedString("") }

        do {
            return try AttributedString(
                markdown: markdown,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
            )
        } catch {
            return AttributedString(markdown)
        }
    }

    static func displayMarkdown(from taskBody: String) -> String {
        TaskChecklistMarkdown.notes(in: taskBody)
    }
}

struct MarkdownBodyView: View {
    let taskBody: String

    var body: some View {
        Text(renderedText)
            .font(.body)
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var renderedText: AttributedString {
        let plainText = MarkdownBodyRenderer.displayMarkdown(from: taskBody)
        return (try? MarkdownBodyRenderer.renderedText(from: taskBody)) ?? AttributedString(plainText)
    }
}
