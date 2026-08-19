import SwiftUI

@main
struct MemosNativeApp: App {
    @State private var session = AppSession()
    @AppStorage("appearancePreference") private var appearance = AppearancePreference.system.rawValue

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(session)
                .tint(AppTheme.tint)
                .preferredColorScheme(AppearancePreference(rawValue: appearance)?.colorScheme)
        }
    }
}

private struct AppRootView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Group {
            if session.isRestoring {
                LaunchView()
            } else if let api = session.api, let user = session.user {
                MainTabView(session: session, api: api, user: user)
                    .transition(.opacity.combined(with: .scale(scale: 0.99)))
            } else {
                ConnectionView(session: session)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.isAuthenticated)
        .task {
            if session.isRestoring {
                await session.restore()
            }
        }
    }
}

private struct LaunchView: View {
    @State private var appeared = false

    var body: some View {
        ZStack {
            AppTheme.warmBackground.ignoresSafeArea()
            VStack(spacing: 18) {
                BrandMark(size: 76)
                    .scaleEffect(appeared ? 1 : 0.88)
                    .opacity(appeared ? 1 : 0)
                ProgressView()
                    .controlSize(.small)
                    .tint(.secondary)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                appeared = true
            }
        }
    }
}
