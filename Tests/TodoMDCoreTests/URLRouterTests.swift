import XCTest
@testable import TodoMDCore

final class URLRouterTests: XCTestCase {
    func testAddTaskURL() throws {
        let router = URLRouter()
        let url = URL(string: "todomd://add?title=Buy+milk&due=2025-03-01&due_time=17:45&tags=errands,food")!
        let action = try router.parse(url: url)

        switch action {
        case .addTask(let request):
            XCTAssertEqual(request.title, "Buy milk")
            XCTAssertEqual(request.due?.isoString, "2025-03-01")
            XCTAssertEqual(request.dueTime?.isoString, "17:45")
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

    func testAddTaskURLDecodesPercentEncoding() throws {
        let router = URLRouter()
        let url = URL(string: "todomd://add?title=Plan%20A%2BB&project=Work%2FOps&tags=one%2Ctwo%2Bthree")!
        let action = try router.parse(url: url)

        switch action {
        case .addTask(let request):
            XCTAssertEqual(request.title, "Plan A+B")
            XCTAssertEqual(request.project, "Work/Ops")
            XCTAssertEqual(request.tags, ["one", "two+three"])
        default:
            XCTFail("Expected addTask action")
        }
    }

    func testTaskURL() throws {
        let router = URLRouter()
        let path = "/Users/hans/Library/Mobile Documents/com~apple~CloudDocs/todo.md/Task.md"
        var components = URLComponents()
        components.scheme = "todomd"
        components.host = "task"
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        let url = try XCTUnwrap(components.url)
        let action = try router.parse(url: url)

        switch action {
        case .showTask(let resolvedPath):
            XCTAssertEqual(resolvedPath, path)
        default:
            XCTFail("Expected showTask action")
        }
    }

    func testQuickAddURL() throws {
        let router = URLRouter()
        let url = URL(string: "todomd://quick-add")!
        let action = try router.parse(url: url)

        switch action {
        case .quickAdd:
            break
        default:
            XCTFail("Expected quickAdd action")
        }
    }

    func testTaskRefURL() throws {
        let router = URLRouter()
        let action = try router.parse(url: URL(string: "todomd://task/t-3f8a")!)

        switch action {
        case .showTaskRef(let ref):
            XCTAssertEqual(ref, "t-3f8a")
        default:
            XCTFail("Expected showTaskRef action")
        }
    }
}
