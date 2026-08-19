import Foundation

enum MemoVisibility: String, Codable, CaseIterable, Identifiable, Sendable {
    case privateMemo = "PRIVATE"
    case protectedMemo = "PROTECTED"
    case publicMemo = "PUBLIC"
    case unspecified = "VISIBILITY_UNSPECIFIED"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privateMemo: "Private"
        case .protectedMemo: "Members"
        case .publicMemo: "Public"
        case .unspecified: "Private"
        }
    }

    var systemImage: String {
        switch self {
        case .privateMemo, .unspecified: "lock.fill"
        case .protectedMemo: "person.2.fill"
        case .publicMemo: "globe.americas.fill"
        }
    }

    static var selectableCases: [MemoVisibility] {
        [.privateMemo, .protectedMemo, .publicMemo]
    }
}

enum MemoState: String, Codable, Sendable {
    case normal = "NORMAL"
    case archived = "ARCHIVED"
    case unspecified = "STATE_UNSPECIFIED"
}

struct Memo: Codable, Identifiable, Hashable, Sendable {
    let name: String
    var state: MemoState
    let creator: String
    let createTime: Date
    var updateTime: Date
    var content: String
    var visibility: MemoVisibility
    var tags: [String]
    var pinned: Bool
    var attachments: [MemoAttachment]
    var property: MemoProperty?
    var parent: String?
    var snippet: String?

    var id: String { name }
    var resourceID: String { name.split(separator: "/").last.map(String.init) ?? name }

    var displayTitle: String? {
        if let title = property?.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        guard let first = content.split(whereSeparator: \Character.isNewline).first else { return nil }
        let cleaned = String(first)
            .replacingOccurrences(of: #"^#{1,6}\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return cleaned.count <= 72 ? cleaned : nil
    }

    private enum CodingKeys: String, CodingKey {
        case name, state, creator, createTime, updateTime, content, visibility, tags, pinned
        case attachments, property, parent, snippet
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        state = try container.decodeIfPresent(MemoState.self, forKey: .state) ?? .normal
        creator = try container.decodeIfPresent(String.self, forKey: .creator) ?? ""
        createTime = try container.decodeIfPresent(Date.self, forKey: .createTime) ?? .now
        updateTime = try container.decodeIfPresent(Date.self, forKey: .updateTime) ?? createTime
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        visibility = try container.decodeIfPresent(MemoVisibility.self, forKey: .visibility) ?? .privateMemo
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        attachments = try container.decodeIfPresent([MemoAttachment].self, forKey: .attachments) ?? []
        property = try container.decodeIfPresent(MemoProperty.self, forKey: .property)
        parent = try container.decodeIfPresent(String.self, forKey: .parent)
        snippet = try container.decodeIfPresent(String.self, forKey: .snippet)
    }

    init(
        name: String,
        state: MemoState = .normal,
        creator: String = "",
        createTime: Date = .now,
        updateTime: Date = .now,
        content: String,
        visibility: MemoVisibility = .privateMemo,
        tags: [String] = [],
        pinned: Bool = false,
        attachments: [MemoAttachment] = [],
        property: MemoProperty? = nil,
        parent: String? = nil,
        snippet: String? = nil
    ) {
        self.name = name
        self.state = state
        self.creator = creator
        self.createTime = createTime
        self.updateTime = updateTime
        self.content = content
        self.visibility = visibility
        self.tags = tags
        self.pinned = pinned
        self.attachments = attachments
        self.property = property
        self.parent = parent
        self.snippet = snippet
    }
}

struct MemoProperty: Codable, Hashable, Sendable {
    let hasLink: Bool?
    let hasTaskList: Bool?
    let hasCode: Bool?
    let hasIncompleteTasks: Bool?
    let title: String?
}

struct MemoAttachment: Codable, Identifiable, Hashable, Sendable {
    let name: String
    let createTime: Date?
    let filename: String
    let content: String?
    let externalLink: String?
    let type: String?
    let size: String?
    let memo: String?

    var id: String { name }
    var isImage: Bool { type?.lowercased().hasPrefix("image/") == true }

    private enum CodingKeys: String, CodingKey {
        case name, createTime, filename, content, externalLink, type, size, memo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? UUID().uuidString
        createTime = try container.decodeIfPresent(Date.self, forKey: .createTime)
        filename = try container.decodeIfPresent(String.self, forKey: .filename) ?? "Attachment"
        content = try container.decodeIfPresent(String.self, forKey: .content)
        externalLink = try container.decodeIfPresent(String.self, forKey: .externalLink)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        if let string = try? container.decode(String.self, forKey: .size) {
            size = string
        } else if let integer = try? container.decode(Int64.self, forKey: .size) {
            size = String(integer)
        } else {
            size = nil
        }
        memo = try container.decodeIfPresent(String.self, forKey: .memo)
    }
}

struct MemosResponse: Codable, Sendable {
    let memos: [Memo]
    let nextPageToken: String?
}

struct MemosUser: Codable, Hashable, Sendable {
    let name: String
    let role: String?
    let username: String
    let email: String?
    let displayName: String?
    let avatarUrl: String?
    let description: String?

    var preferredName: String {
        let display = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return display.isEmpty ? username : display
    }
}

struct CurrentUserResponse: Codable, Sendable {
    let user: MemosUser
}

struct SignInResponse: Codable, Sendable {
    let user: MemosUser
    let accessToken: String
    let accessTokenExpiresAt: Date?
}

struct RefreshTokenResponse: Codable, Sendable {
    let accessToken: String
    let accessTokenExpiresAt: Date?
}

struct APIStatus: Codable, Sendable {
    let code: Int?
    let message: String?
}

struct CreateAttachmentBody: Encodable, Sendable {
    let filename: String
    let content: String
    let type: String
}

struct CreateMemoBody: Encodable, Sendable {
    let state = MemoState.normal
    let content: String
    let visibility: MemoVisibility
    let attachments: [CreateAttachmentBody]
}

struct UpdateMemoBody: Encodable, Sendable {
    let name: String
    let state: MemoState
    let content: String
    let visibility: MemoVisibility
    let pinned: Bool
}

extension Date {
    var memoRelativeText: String {
        let seconds = max(0, Date.now.timeIntervalSince(self))
        switch seconds {
        case ..<45:
            return "Now"
        case ..<3_600:
            return "\(Int(seconds / 60))m ago"
        case ..<86_400:
            return "\(Int(seconds / 3_600))h ago"
        case ..<604_800:
            return "\(Int(seconds / 86_400))d ago"
        default:
            return formatted(date: .abbreviated, time: .omitted)
        }
    }
}
