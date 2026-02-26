import XCTest
@testable import TodoMDCore

final class URLRouterTests: XCTestCase {
    func testAddTaskURL() throws {
        let router = URLRouter()
        let url = URL(string: "todomd://add?title=Buy+milk&due=2025-03-01&tags=errands,food")!
        let action = try router.parse(url: url)

        switch action {
        case .addTask(let request):
            XCTAssertEqual(request.title, "Buy milk")
            XCTAssertEqual(request.due?.isoString, "2025-03-01")
            XCTAssertEqual(request.tags, ["errands", "food"])
        default:
            XCTFail("Expected addTask action")
        }
    }

    func testShowViewURL() throws {
        let router = URLRouter()
        let url = URL(string: "todomd://show/today")!
        let action = try router.parse(url: url)

        switch action {
        case .showView(let view):
            XCTAssertEqual(view.rawValue, "today")
        default:
            XCTFail("Expected showView action")
        }
    }
}
