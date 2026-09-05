import XCTest
@testable import MacTidy

final class ResultPageTests: XCTestCase {
    func testEveryResultIsReachableExactlyOnce() {
        for count in [0, 1, 49, 50, 51, 5_003] {
            var visited: [Int] = []
            var index = 0
            while true {
                let page = ResultPage(count: count, requestedIndex: index)
                XCTAssertLessThanOrEqual(page.range.count, ResultPage.size)
                XCTAssertEqual(page.hasPrevious, index > 0)
                visited.append(contentsOf: page.range)
                guard page.hasNext else { break }
                index += 1
            }
            XCTAssertEqual(visited, Array(0..<count))
        }
    }

    func testFilteringClampsStalePagesWithoutLosingResults() {
        let filtered = ResultPage(count: 3, requestedIndex: 99)
        XCTAssertEqual(filtered.index, 0)
        XCTAssertEqual(filtered.range, 0..<3)
        XCTAssertFalse(filtered.hasPrevious)
        XCTAssertFalse(filtered.hasNext)

        let empty = ResultPage(count: 0, requestedIndex: 99)
        XCTAssertTrue(empty.range.isEmpty)
        XCTAssertEqual(ResultPage(count: 51, requestedIndex: 99).range, 50..<51)
        XCTAssertEqual(ResultPage(count: 51, requestedIndex: -1).range, 0..<50)
    }
}
