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

    func testMemoCreationUsesUploadedAttachmentReferences() throws {
        let body = CreateMemoBody(
            content: "Photo memo",
            visibility: .privateMemo,
            attachments: [AttachmentReferenceBody(name: "attachments/photo-123")]
        )
        let data = try JSONEncoder().encode(body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let attachments = try XCTUnwrap(json["attachments"] as? [[String: Any]])
        let attachment = try XCTUnwrap(attachments.first)

        XCTAssertEqual(attachment["name"] as? String, "attachments/photo-123")
        XCTAssertNil(attachment["content"])
        XCTAssertNil(attachment["filename"])
    }
}
