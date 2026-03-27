import Foundation
import Testing
@testable import TodoMDApp

@Suite
struct MarkdownBodyViewTests {
    @Test("Renderer strips managed checklist items while preserving markdown formatting")
    func rendererStripsManagedChecklistItemsWhilePreservingLinks() throws {
        let rendered = try MarkdownBodyRenderer.renderedText(from: """
        ## Notes

        - Buy **organic** eggs
        - Check [this recipe](https://example.com)
        - Code: `git pull && swift build`

        <!-- todo.md checklist -->
        - [ ] hidden checklist item
        """)

        let renderedText = String(rendered.characters)
        #expect(renderedText.contains("Notes"))
        #expect(renderedText.contains("Buy organic eggs"))
        #expect(renderedText.contains("Check this recipe"))
        #expect(renderedText.contains("Code: git pull && swift build"))
        #expect(!renderedText.contains("hidden checklist item"))
        #expect(rendered.runs.contains(where: { $0.link == URL(string: "https://example.com")! }))
    }

    @Test("Renderer preserves boundary whitespace that markdown syntax depends on")
    func rendererPreservesWhitespaceSensitiveMarkdownBoundaries() {
        let markdown = MarkdownBodyRenderer.displayMarkdown(from: "    let value = 42\n\ntrailing  ")

        #expect(markdown.hasPrefix("    let value = 42"))
        #expect(markdown.hasSuffix("trailing  "))
    }
}
