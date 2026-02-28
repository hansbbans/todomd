import XCTest
@testable import TodoMDCore

final class TaskReferenceServicesTests: XCTestCase {
    func testGeneratedRefsMatchExpectedPatternAndAreUnique() {
        let generator = TaskRefGenerator()
        var refs: Set<String> = []

        for _ in 0..<1_000 {
            let ref = generator.generate(existingRefs: refs)
            XCTAssertTrue(TaskRefGenerator.isValid(ref: ref))
            XCTAssertFalse(refs.contains(ref))
            refs.insert(ref)
        }
    }

    func testResolverFindsRecordsByRef() {
        var frontmatter = TestSupport.sampleFrontmatter(title: "Task A")
        frontmatter.ref = "t-0a0a"
        let record = TaskRecord(
            identity: TaskFileIdentity(path: "/tmp/a.md"),
            document: TaskDocument(frontmatter: frontmatter, body: "")
        )

        let resolver = TaskRefResolver(records: [record])
        XCTAssertEqual(resolver.resolve(ref: "t-0a0a")?.identity.path, "/tmp/a.md")
        XCTAssertNil(resolver.resolve(ref: "t-missing"))
    }
}
