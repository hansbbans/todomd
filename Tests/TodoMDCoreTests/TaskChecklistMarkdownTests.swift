import XCTest
@testable import TodoMDCore

final class TaskChecklistMarkdownTests: XCTestCase {
    func testParseExtractsOnlyExplicitManagedChecklistBlock() {
        let markdown = """
        Intro paragraph

        - [ ] Example syntax

        <!-- todo.md checklist -->
        * [x] Charger
        [ ] Adapter
        """

        let items = TaskChecklistMarkdown.parse(markdown)

        XCTAssertEqual(items.map(\.title), ["Charger", "Adapter"])
        XCTAssertEqual(items.map(\.isCompleted), [true, false])
        XCTAssertEqual(
            TaskChecklistMarkdown.notes(in: markdown),
            """
            Intro paragraph

            - [ ] Example syntax
            """
        )
    }

    func testToggleItemUpdatesOnlyRequestedChecklistLine() {
        let markdown = """
        Intro paragraph

        <!-- todo.md checklist -->
        - [ ] Passport
        - [x] Charger
        """

        let updated = TaskChecklistMarkdown.toggleItem(in: markdown, at: 0)

        XCTAssertEqual(
            updated,
            """
            Intro paragraph

            <!-- todo.md checklist -->
            - [x] Passport
            - [x] Charger
            """
        )
    }

    func testDeleteItemRemovesOnlyRequestedChecklistLine() {
        let markdown = """
        Notes

        <!-- todo.md checklist -->
        - [ ] Passport
        - [x] Charger
        """

        let updated = TaskChecklistMarkdown.deleteItem(in: markdown, at: 0)

        XCTAssertEqual(
            updated,
            """
            Notes

            <!-- todo.md checklist -->
            - [x] Charger
            """
        )
    }

    func testAddItemAppendsMarkdownCheckboxLine() {
        let markdown = """
        Notes about the trip.
        """

        let updated = TaskChecklistMarkdown.addItem(to: markdown, title: "Passport")

        XCTAssertEqual(
            updated,
            """
            Notes about the trip.

            <!-- todo.md checklist -->
            - [ ] Passport
            """
        )
    }

    func testCheckboxLookingTextInNotesIsNotManagedChecklist() {
        let markdown = """
        Notes
        - [ ] Example syntax

        More notes.
        """

        XCTAssertTrue(TaskChecklistMarkdown.parse(markdown).isEmpty)
        XCTAssertEqual(TaskChecklistMarkdown.notes(in: markdown), markdown)
    }

    func testMarkerWithNonChecklistContentFallsBackToNotesOnly() {
        let markdown = """
        Notes

        <!-- todo.md checklist -->
        - [ ] Passport
        This should stay in notes.
        """

        XCTAssertTrue(TaskChecklistMarkdown.parse(markdown).isEmpty)
        XCTAssertEqual(TaskChecklistMarkdown.notes(in: markdown), markdown)
    }

    func testReplacingNotesPreservesTrailingChecklistBlock() {
        let markdown = """
        Notes about the trip.

        <!-- todo.md checklist -->
        - [ ] Passport
        - [x] Charger
        """

        let updated = TaskChecklistMarkdown.replaceNotes(in: markdown, with: "Updated notes")

        XCTAssertEqual(
            updated,
            """
            Updated notes

            <!-- todo.md checklist -->
            - [ ] Passport
            - [x] Charger
            """
        )
    }
}
