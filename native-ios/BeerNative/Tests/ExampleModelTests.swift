import XCTest
@testable import BeerNative  // Note: requires test target setup in XcodeGen for real runs

// Theme 1 correction: basic test scaffolding for models (expand with mocks for BeerAPI).
// Run via xcodebuild test after wiring a test target in project.yml.

final class ExampleModelTests: XCTestCase {
    func testPendingCheckinEquality() throws {
        let now = Date()
        let p1 = PendingCheckin(id: UUID(), createdAt: now, barcode: "123", beerName: "Test", brewery: "B", style: "S", abv: "5", summary: "", rating: 4.0, flavors: [], hops: [], comment: "", untappdBid: nil, force: false, photoJPEGBase64: nil)
        let p2 = p1
        XCTAssertEqual(p1.beerName, p2.beerName)
        XCTAssertEqual(p1.rating, 4.0)
    }

    // TODO: add tests for ServerSettings.lanApiBase, OfflineQueue enqueue dedup, cache save/load, etc.
    // Mock BeerAPI for unit testing discover / baseURL logic.
}