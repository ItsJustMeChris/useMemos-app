import SwiftUI

struct ConnectionView: View {
    let session: AppSession

    @State private var server = ""
    @State private var authenticationKind = AuthenticationKind.personalAccessToken
    @State private var token = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?
    @Environment(\.openURL) private var openURL

    private enum Field { case server, token, username, password }

    var body: some View {
        ZStack {
            AppTheme.warmBackground.ignoresSafeArea()
            decorativeBackground

            ScrollView {
                VStack(spacing: 28) {
                    brandHeader
                    connectionCard
                    privacyNote
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 20)
                .padding(.vertical, 38)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var decorativeBackground: some View {
        GeometryReader { proxy in
            Circle()
                .fill(AppTheme.tint.opacity(0.08))
                .frame(width: 380, height: 380)
                .blur(radius: 8)
                .offset(x: proxy.size.width * 0.47, y: -170)
            Circle()
                .fill(Color.teal.opacity(0.055))
                .frame(width: 310, height: 310)
                .blur(radius: 10)
                .offset(x: -160, y: proxy.size.height * 0.62)
        }
        .allowsHitTesting(false)
    }

    private var brandHeader: some View {
        VStack(spacing: 18) {
            BrandMark(size: 76)
            VStack(spacing: 7) {
                Text("Your memos, at hand")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("A focused, native home for your self-hosted Memos.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Connect your server")
                    .font(.title3.bold())
                Text("Enter the address you normally use to open Memos.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Server address")
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 10) {
                    Image(systemName: "network")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    TextField("memos.example.com", text: $server)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .focused($focusedField, equals: .server)
                        .submitLabel(.next)
                        .onSubmit { focusedField = authenticationKind == .personalAccessToken ? .token : .username }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 50)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }

            Picker("Sign-in method", selection: $authenticationKind) {
                Text("Access token").tag(AuthenticationKind.personalAccessToken)
                Text("Password").tag(AuthenticationKind.password)
            }
            .pickerStyle(.segmented)

            Group {
                if authenticationKind == .personalAccessToken {
                    tokenFields
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                } else {
                    passwordFields
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: authenticationKind)

            if let message = errorMessage ?? session.restorationMessage {
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: connect) {
                HStack(spacing: 10) {
                    if isConnecting {
                        ProgressView().tint(.white)
                    }
                    Text(isConnecting ? "Connecting…" : "Connect")
                        .fontWeight(.semibold)
                    if !isConnecting { Image(systemName: "arrow.right") }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .disabled(isConnecting || server.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(0.07), radius: 24, y: 12)
    }

    private var tokenFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Personal access token")
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 10) {
                    Image(systemName: "key.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    SecureField("memos_pat_…", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.password)
                        .focused($focusedField, equals: .token)
                        .submitLabel(.go)
                        .onSubmit(connect)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 50)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }

            Label("Recommended. Create a dedicated token in Memos under Settings → Access tokens.", systemImage: "checkmark.shield.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var passwordFields: some View {
        VStack(spacing: 12) {
            credentialField(title: "Username", icon: "person.fill", field: .username) {
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                    .focused($focusedField, equals: .username)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
            }
            credentialField(title: "Password", icon: "lock.fill", field: .password) {
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .onSubmit(connect)
            }
            Text("Works with Memos password sign-in. Servers that require SSO should use an access token.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func credentialField<Content: View>(
        title: String,
        icon: String,
        field: Field,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                content()
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
    }

    private var privacyNote: some View {
        Label("Your credentials stay in the iOS Keychain. Your memos travel directly between this device and your server.", systemImage: "lock.shield.fill")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 460)
    }

    private func connect() {
        guard !isConnecting else { return }
        focusedField = nil
        errorMessage = nil
        isConnecting = true

        Task {
            defer { isConnecting = false }
            do {
                switch authenticationKind {
                case .personalAccessToken:
                    try await session.connect(serverInput: server, personalAccessToken: token)
                case .password:
                    try await session.signIn(serverInput: server, username: username, password: password)
                }
            } catch {
                errorMessage = error.localizedDescription
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
}

