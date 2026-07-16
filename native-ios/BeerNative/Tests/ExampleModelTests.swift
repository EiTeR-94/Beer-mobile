import XCTest
@testable import BeerNative

final class ExampleModelTests: XCTestCase {
    func testPendingCheckinEquality() throws {
        let now = Date()
        let p1 = PendingCheckin(
            id: UUID(),
            createdAt: now,
            barcode: "123",
            beerName: "Test",
            brewery: "B",
            style: "S",
            abv: "5",
            summary: "",
            rating: 4.0,
            flavors: [],
            hops: [],
            comment: "",
            untappdBid: "",
            force: false,
            photoJPEGBase64: nil,
            location: nil
        )
        XCTAssertEqual(p1.beerName, "Test")
        XCTAssertEqual(p1.rating, 4.0)
        XCTAssertNil(p1.location)
    }
}
