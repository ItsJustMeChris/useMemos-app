import Foundation

enum ServerURL {
    static func normalize(_ input: String) throws -> URL {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw ServerURLError.empty }

        if !value.contains("://") {
            value = "https://\(value)"
        }

        guard var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host,
              !host.isEmpty else {
            throw ServerURLError.invalid
        }

        components.scheme = scheme
        components.query = nil
        components.fragment = nil

        var path = components.path
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        if path.hasSuffix("/api/v1") {
            path.removeLast("/api/v1".count)
        }
        components.path = path == "/" ? "" : path

        guard let url = components.url else { throw ServerURLError.invalid }
        return url
    }
}

enum ServerURLError: LocalizedError {
    case empty
    case invalid

    var errorDescription: String? {
        switch self {
        case .empty: "Enter the address of your Memos server."
        case .invalid: "That doesn’t look like a valid Memos server address."
        }
    }
}

