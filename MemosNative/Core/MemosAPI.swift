import Foundation

enum AuthenticationKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case personalAccessToken
    case password

    var id: String { rawValue }
}

actor MemosAPI {
    nonisolated let baseURL: URL
    private let session: URLSession
    private var accessToken: String
    private let authenticationKind: AuthenticationKind
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURL: URL, accessToken: String = "", authenticationKind: AuthenticationKind) {
        self.baseURL = baseURL
        self.accessToken = accessToken
        self.authenticationKind = authenticationKind

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 90
        configuration.waitsForConnectivity = true
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        configuration.requestCachePolicy = .reloadRevalidatingCacheData
        self.session = URLSession(configuration: configuration)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = ISO8601DateFormatter.fractional.date(from: value)
                ?? ISO8601DateFormatter.standard.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date: \(value)")
        }
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    func signIn(username: String, password: String) async throws -> SignInResponse {
        struct PasswordCredentials: Encodable { let username: String; let password: String }
        struct SignInBody: Encodable { let passwordCredentials: PasswordCredentials }

        let body = SignInBody(passwordCredentials: .init(username: username, password: password))
        let response: SignInResponse = try await request(
            path: "auth/signin",
            method: "POST",
            body: encoder.encode(body),
            requiresAuthentication: false
        )
        accessToken = response.accessToken
        try KeychainStore.save(response.accessToken)
        return response
    }

    func currentUser() async throws -> MemosUser {
        let response: CurrentUserResponse = try await request(path: "auth/me")
        return response.user
    }

    func listMemos(
        state: MemoState = .normal,
        pageSize: Int = 50,
        pageToken: String? = nil,
        filter: String? = nil
    ) async throws -> MemosResponse {
        var query = [
            URLQueryItem(name: "state", value: state.rawValue),
            URLQueryItem(name: "pageSize", value: String(pageSize)),
            URLQueryItem(name: "orderBy", value: "pinned desc, create_time desc")
        ]
        if let pageToken, !pageToken.isEmpty {
            query.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        if let filter, !filter.isEmpty {
            query.append(URLQueryItem(name: "filter", value: filter))
        }
        return try await request(path: "memos", query: query)
    }

    func createMemo(
        content: String,
        visibility: MemoVisibility,
        attachments: [CreateAttachmentBody] = []
    ) async throws -> Memo {
        var uploadedAttachments: [MemoAttachment] = []
        do {
            for attachment in attachments {
                uploadedAttachments.append(try await createAttachment(attachment))
            }

            let references = uploadedAttachments.map { AttachmentReferenceBody(name: $0.name) }
            let body = CreateMemoBody(content: content, visibility: visibility, attachments: references)
            return try await request(path: "memos", method: "POST", body: encoder.encode(body))
        } catch {
            for attachment in uploadedAttachments {
                try? await deleteAttachment(attachment)
            }
            throw error
        }
    }

    private func createAttachment(_ attachment: CreateAttachmentBody) async throws -> MemoAttachment {
        try await request(
            path: "attachments",
            method: "POST",
            body: encoder.encode(attachment)
        )
    }

    private func deleteAttachment(_ attachment: MemoAttachment) async throws {
        let _: EmptyResponse = try await request(
            path: "attachments/\(attachment.resourceID)",
            method: "DELETE"
        )
    }

    func updateMemo(_ memo: Memo) async throws -> Memo {
        let body = UpdateMemoBody(
            name: memo.name,
            state: memo.state,
            content: memo.content,
            visibility: memo.visibility,
            pinned: memo.pinned
        )
        let query = [URLQueryItem(name: "updateMask", value: "content,visibility,state,pinned")]
        return try await request(
            path: "memos/\(memo.resourceID)",
            method: "PATCH",
            query: query,
            body: encoder.encode(body)
        )
    }

    func setPinned(_ pinned: Bool, for memo: Memo) async throws -> Memo {
        struct Body: Encodable { let name: String; let pinned: Bool }
        let query = [URLQueryItem(name: "updateMask", value: "pinned")]
        return try await request(
            path: "memos/\(memo.resourceID)",
            method: "PATCH",
            query: query,
            body: encoder.encode(Body(name: memo.name, pinned: pinned))
        )
    }

    func setArchived(_ archived: Bool, for memo: Memo) async throws -> Memo {
        struct Body: Encodable { let name: String; let state: MemoState }
        let state: MemoState = archived ? .archived : .normal
        let query = [URLQueryItem(name: "updateMask", value: "state")]
        return try await request(
            path: "memos/\(memo.resourceID)",
            method: "PATCH",
            query: query,
            body: encoder.encode(Body(name: memo.name, state: state))
        )
    }

    func deleteMemo(_ memo: Memo) async throws {
        let _: EmptyResponse = try await request(path: "memos/\(memo.resourceID)", method: "DELETE")
    }

    nonisolated func webURL(for memo: Memo) -> URL {
        baseURL.appending(path: "m/\(memo.resourceID)")
    }

    private func request<Response: Decodable>(
        path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: Data? = nil,
        requiresAuthentication: Bool = true,
        mayRefresh: Bool = true
    ) async throws -> Response {
        let request = try makeRequest(
            path: path,
            method: method,
            query: query,
            body: body,
            requiresAuthentication: requiresAuthentication
        )

        do {
            return try await perform(request)
        } catch APIError.unauthorized where authenticationKind == .password && mayRefresh {
            try await refreshAccessToken()
            return try await self.request(
                path: path,
                method: method,
                query: query,
                body: body,
                requiresAuthentication: requiresAuthentication,
                mayRefresh: false
            )
        }
    }

    private func makeRequest(
        path: String,
        method: String,
        query: [URLQueryItem],
        body: Data?,
        requiresAuthentication: Bool
    ) throws -> URLRequest {
        let apiRoot = baseURL.appending(path: "api/v1")
        guard var components = URLComponents(url: apiRoot.appending(path: path), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = method == "GET" ? 30 : 60
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if requiresAuthentication, !accessToken.isEmpty {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw APIError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw APIError.unauthorized }
            let status = try? decoder.decode(APIStatus.self, from: data)
            throw APIError.server(statusCode: http.statusCode, message: status?.message)
        }

        if Response.self == EmptyResponse.self, data.isEmpty || data == Data("{}".utf8) {
            return EmptyResponse() as! Response
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    private func refreshAccessToken() async throws {
        let response: RefreshTokenResponse = try await request(
            path: "auth/refresh",
            method: "POST",
            body: Data("{}".utf8),
            requiresAuthentication: false,
            mayRefresh: false
        )
        accessToken = response.accessToken
        try KeychainStore.save(response.accessToken)
    }
}

private struct EmptyResponse: Codable, Sendable {}

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case transport(URLError)
    case server(statusCode: Int, message: String?)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "The server address is invalid."
        case .invalidResponse:
            "The server returned an unexpected response."
        case .unauthorized:
            "Memos couldn’t verify these credentials. Check them and try again."
        case .transport(let error):
            switch error.code {
            case .notConnectedToInternet: "You appear to be offline."
            case .cannotFindHost, .dnsLookupFailed: "That Memos server couldn’t be found."
            case .cannotConnectToHost, .timedOut: "The Memos server didn’t respond."
            case .secureConnectionFailed, .serverCertificateUntrusted: "The server’s secure connection couldn’t be verified."
            default: "Couldn’t reach the Memos server. \(error.localizedDescription)"
            }
        case .server(let code, let message):
            message?.isEmpty == false ? message : "The server returned an error (\(code))."
        case .decoding:
            "This server returned data in a format the app doesn’t recognize. It may be running an incompatible Memos version."
        }
    }
}

private extension ISO8601DateFormatter {
    static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let standard = ISO8601DateFormatter()
}
