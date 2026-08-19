import XCTest
@testable import MemosNative

final class ModelDecodingTests: XCTestCase {
    func testDecodesCurrentMemoResponse() throws {
        let json = #"""
        {
          "memos": [{
            "name": "memos/abc123",
            "state": "NORMAL",
            "creator": "users/chris",
            "createTime": "2026-08-19T15:21:34.123Z",
            "updateTime": "2026-08-19T15:25:00Z",
            "content": "# Hello\n- [ ] Ship it #work",
            "visibility": "PRIVATE",
            "tags": ["work"],
            "pinned": true,
            "attachments": []
          }],
          "nextPageToken": "next"
        }
        """#

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad date")
        }

        let response = try decoder.decode(MemosResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.memos.first?.resourceID, "abc123")
        XCTAssertEqual(response.memos.first?.tags, ["work"])
        XCTAssertEqual(response.memos.first?.visibility, .privateMemo)
        XCTAssertEqual(response.nextPageToken, "next")
    }

    func testDecodesNumericAttachmentSize() throws {
        let json = #"""
        {
          "name": "attachments/photo",
          "filename": "photo.jpg",
          "type": "image/jpeg",
          "size": 2048
        }
        """#
        let attachment = try JSONDecoder().decode(MemoAttachment.self, from: Data(json.utf8))
        XCTAssertEqual(attachment.size, "2048")
        XCTAssertTrue(attachment.isImage)
    }
}
