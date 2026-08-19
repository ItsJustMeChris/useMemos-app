import XCTest
@testable import MemosNative

final class ServerURLTests: XCTestCase {
    func testAddsSecureScheme() throws {
        let url = try ServerURL.normalize("memos.example.com")
        XCTAssertEqual(url.absoluteString, "https://memos.example.com")
    }

    func testRemovesAPISuffixAndTrailingSlash() throws {
        let url = try ServerURL.normalize("https://memos.example.com/notes/api/v1/")
        XCTAssertEqual(url.absoluteString, "https://memos.example.com/notes")
    }

    func testKeepsExplicitLocalHTTP() throws {
        let url = try ServerURL.normalize("http://192.168.1.25:5230/")
        XCTAssertEqual(url.absoluteString, "http://192.168.1.25:5230")
    }

    func testRejectsUnsupportedScheme() {
        XCTAssertThrowsError(try ServerURL.normalize("ftp://example.com"))
    }
}

