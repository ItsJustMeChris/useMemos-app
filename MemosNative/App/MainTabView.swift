import SwiftUI

struct MainTabView: View {
    let session: AppSession
    let api: MemosAPI
    let user: MemosUser

    @State private var store: MemoStore
    @State private var selectedTab = AppTab.timeline
    @State private var showingComposer = false

    init(session: AppSession, api: MemosAPI, user: MemosUser) {
        self.session = session
        self.api = api
        self.user = user
        _store = State(initialValue: MemoStore(api: api, ownerName: user.name))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            TimelineView(store: store, user: user, showingComposer: $showingComposer)
                .tabItem { Label("Memos", systemImage: "square.text.square.fill") }
                .tag(AppTab.timeline)

            SearchView(store: store)
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(AppTab.search)

            ArchiveView(store: store)
                .tabItem { Label("Archive", systemImage: "archivebox.fill") }
                .tag(AppTab.archive)

            SettingsView(session: session, store: store, user: user)
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .sheet(isPresented: $showingComposer) {
            ComposerView(store: store)
        }
        .overlay(alignment: .top) {
            if let message = session.restorationMessage {
                OfflineBanner(message: message) {
                    Task { await session.retryConnection() }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

private enum AppTab: Hashable {
    case timeline, search, archive, settings
}

struct OfflineBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Working offline").font(.subheadline.weight(.semibold))
                Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Button("Retry", action: retry)
                .font(.subheadline.weight(.semibold))
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.orange.opacity(0.25), lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
    }
}
