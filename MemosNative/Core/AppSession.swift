import Foundation
import Observation

struct SavedConnection: Codable, Hashable, Sendable {
    let serverURL: URL
    let authenticationKind: AuthenticationKind
}

@MainActor
@Observable
final class AppSession {
    private(set) var connection: SavedConnection?
    private(set) var user: MemosUser?
    private(set) var api: MemosAPI?
    private(set) var isRestoring = true
    var restorationMessage: String?

    private let defaults: UserDefaults
    private let connectionKey = "activeConnection"
    private let cachedUserKey = "cachedUser"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--demo-content") {
            let serverURL = URL(string: "https://memos.example.com")!
            connection = SavedConnection(serverURL: serverURL, authenticationKind: .personalAccessToken)
            user = MemosUser(
                name: "users/chris",
                role: "HOST",
                username: "chris",
                email: "chris@example.com",
                displayName: "Chris",
                avatarUrl: nil,
                description: nil
            )
            api = MemosAPI(baseURL: serverURL, accessToken: "demo", authenticationKind: .personalAccessToken)
            isRestoring = false
        }
#endif
    }

    var isAuthenticated: Bool {
        connection != nil && user != nil && api != nil
    }

    func restore() async {
        defer { isRestoring = false }
#if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if let bootstrapServer = environment["MEMOS_BOOTSTRAP_SERVER"],
           let bootstrapToken = environment["MEMOS_BOOTSTRAP_TOKEN"],
           !bootstrapServer.isEmpty,
           !bootstrapToken.isEmpty {
            do {
                try await connect(serverInput: bootstrapServer, personalAccessToken: bootstrapToken)
                return
            } catch {
                restorationMessage = error.localizedDescription
            }
        }
#endif
        guard let connectionData = defaults.data(forKey: connectionKey),
              let saved = try? JSONDecoder().decode(SavedConnection.self, from: connectionData),
              let credential = try? KeychainStore.read(),
              !credential.isEmpty else {
            return
        }

        let client = MemosAPI(
            baseURL: saved.serverURL,
            accessToken: credential,
            authenticationKind: saved.authenticationKind
        )
        connection = saved
        api = client

        if let userData = defaults.data(forKey: cachedUserKey),
           let cached = try? JSONDecoder().decode(MemosUser.self, from: userData) {
            user = cached
        }

        do {
            let refreshedUser = try await client.currentUser()
            try setAuthenticated(connection: saved, user: refreshedUser, api: client, credential: nil)
        } catch APIError.unauthorized {
            disconnect()
            restorationMessage = "Your Memos session has expired. Connect again to continue."
        } catch {
            if user != nil {
                restorationMessage = error.localizedDescription
            } else {
                connection = nil
                api = nil
                restorationMessage = error.localizedDescription
            }
        }
    }

    func connect(serverInput: String, personalAccessToken: String) async throws {
        let serverURL = try ServerURL.normalize(serverInput)
        let token = personalAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw ConnectionError.missingToken }

        let saved = SavedConnection(serverURL: serverURL, authenticationKind: .personalAccessToken)
        let client = MemosAPI(baseURL: serverURL, accessToken: token, authenticationKind: .personalAccessToken)
        let user = try await client.currentUser()
        try setAuthenticated(connection: saved, user: user, api: client, credential: token)
    }

    func signIn(serverInput: String, username: String, password: String) async throws {
        let serverURL = try ServerURL.normalize(serverInput)
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty, !password.isEmpty else { throw ConnectionError.missingCredentials }

        let saved = SavedConnection(serverURL: serverURL, authenticationKind: .password)
        let client = MemosAPI(baseURL: serverURL, authenticationKind: .password)
        let response = try await client.signIn(username: username, password: password)
        try setAuthenticated(connection: saved, user: response.user, api: client, credential: response.accessToken)
    }

    func retryConnection() async {
        guard let api else { return }
        do {
            let user = try await api.currentUser()
            self.user = user
            restorationMessage = nil
            cache(user)
        } catch {
            restorationMessage = error.localizedDescription
        }
    }

    func disconnect() {
        try? KeychainStore.delete()
        let memoCacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "MemosNative", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: memoCacheURL)
        defaults.removeObject(forKey: connectionKey)
        defaults.removeObject(forKey: cachedUserKey)
        connection = nil
        user = nil
        api = nil
        restorationMessage = nil
        HTTPCookieStorage.shared.removeCookies(since: .distantPast)
    }

    private func setAuthenticated(
        connection: SavedConnection,
        user: MemosUser,
        api: MemosAPI,
        credential: String?
    ) throws {
        if let credential { try KeychainStore.save(credential) }
        let data = try JSONEncoder().encode(connection)
        defaults.set(data, forKey: connectionKey)
        self.connection = connection
        self.user = user
        self.api = api
        restorationMessage = nil
        cache(user)
    }

    private func cache(_ user: MemosUser) {
        if let data = try? JSONEncoder().encode(user) {
            defaults.set(data, forKey: cachedUserKey)
        }
    }
}

enum ConnectionError: LocalizedError {
    case missingToken
    case missingCredentials

    var errorDescription: String? {
        switch self {
        case .missingToken: "Paste a personal access token to continue."
        case .missingCredentials: "Enter your username and password to continue."
        }
    }
}
