import SwiftUI

struct SettingsView: View {
    let session: AppSession
    let store: MemoStore
    let user: MemosUser

    @AppStorage("appearancePreference") private var appearance = AppearancePreference.system.rawValue
    @AppStorage("defaultMemoVisibility") private var defaultVisibility = MemoVisibility.privateMemo.rawValue
    @State private var showingDisconnectConfirmation = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                profileSection
                serverSection
                preferencesSection
                aboutSection
                disconnectSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.warmBackground)
            .navigationTitle("Settings")
            .confirmationDialog(
                "Disconnect from this server?",
                isPresented: $showingDisconnectConfirmation,
                titleVisibility: .visible
            ) {
                Button("Disconnect", role: .destructive) { session.disconnect() }
            } message: {
                Text("Cached memos and credentials will be removed from this device. Nothing on your server will be changed.")
            }
        }
    }

    private var profileSection: some View {
        Section {
            HStack(spacing: 15) {
                avatar
                VStack(alignment: .leading, spacing: 3) {
                    Text(user.preferredName).font(.headline)
                    Text("@\(user.username)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let email = user.email, !email.isEmpty {
                        Text(email).font(.caption).foregroundStyle(.tertiary)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 6)

            LabeledContent("Memos on device", value: "\(store.memos.count)")
            if let role = user.role {
                LabeledContent("Account", value: role == "HOST" ? "Host" : role.capitalized)
            }
        }
    }

    private var avatar: some View {
        Group {
            if let string = user.avatarUrl,
               let url = avatarURL(string) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        avatarPlaceholder
                    }
                }
            } else {
                avatarPlaceholder
            }
        }
        .frame(width: 54, height: 54)
        .clipShape(Circle())
        .overlay { Circle().stroke(AppTheme.hairline, lineWidth: 1) }
    }

    private var avatarPlaceholder: some View {
        ZStack {
            AppTheme.softTint
            Text(String(user.preferredName.prefix(1)).uppercased())
                .font(.title2.bold())
                .foregroundStyle(AppTheme.tint)
        }
    }

    private var serverSection: some View {
        Section("Server") {
            if let connection = session.connection {
                Button {
                    openURL(connection.serverURL)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "server.rack")
                            .foregroundStyle(AppTheme.tint)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(connection.serverURL.host() ?? connection.serverURL.absoluteString)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text("Open in Safari")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                HStack(spacing: 12) {
                    Image(systemName: connection.authenticationKind == .personalAccessToken ? "key.fill" : "person.badge.key.fill")
                        .foregroundStyle(AppTheme.tint)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(connection.authenticationKind == .personalAccessToken ? "Access token" : "Password session")
                        Text("Stored securely in Keychain")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
    }

    private var preferencesSection: some View {
        Section("Preferences") {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppearancePreference.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }

            Picker("Default visibility", selection: $defaultVisibility) {
                ForEach(MemoVisibility.selectableCases) { option in
                    Label(option.title, systemImage: option.systemImage).tag(option.rawValue)
                }
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("App version", value: appVersion)
            Link(destination: URL(string: "https://usememos.com/docs/integrations/api-access")!) {
                Label("Memos API & tokens", systemImage: "book.closed")
            }
            Link(destination: URL(string: "https://usememos.com")!) {
                Label("About Memos", systemImage: "globe")
            }
        }
    }

    private var disconnectSection: some View {
        Section {
            Button(role: .destructive) {
                showingDisconnectConfirmation = true
            } label: {
                Label("Disconnect this server", systemImage: "rectangle.portrait.and.arrow.right")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private func avatarURL(_ value: String) -> URL? {
        if let url = URL(string: value), url.scheme != nil { return url }
        return session.connection?.serverURL.appending(path: value.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }
}
