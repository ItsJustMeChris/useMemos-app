import SwiftUI

struct SearchView: View {
    let store: MemoStore

    @State private var query = ""
    @State private var results: [Memo] = []
    @State private var isSearching = false
    @State private var searchError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.warmBackground.ignoresSafeArea()
                content
            }
            .navigationTitle("Search")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Words, tags, or phrases")
            .task(id: query) { await performSearch() }
            .task { await store.loadTimelineIfNeeded() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            searchLanding
        } else if isSearching && results.isEmpty {
            ProgressView("Searching your server…")
        } else if let searchError, results.isEmpty {
            ContentUnavailableView {
                Label("Search unavailable", systemImage: "exclamationmark.magnifyingglass")
            } description: {
                Text(searchError)
            } actions: {
                Button("Try again") { Task { await performSearch(immediate: true) } }
            }
        } else if results.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    Text("\(results.count) result\(results.count == 1 ? "" : "s")")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    ForEach(results) { memo in
                        MemoCard(memo: memo, store: store)
                    }
                }
                .frame(maxWidth: 720)
                .padding(16)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var searchLanding: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 16) {
                    ZStack {
                        Circle().fill(AppTheme.softTint)
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(AppTheme.tint)
                    }
                    .frame(width: 56, height: 56)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Find anything")
                            .font(.title.bold())
                        Text("Search the content of every memo on your server. Try a person, project, phrase, or hashtag.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 16) {
                        Label("Memo content", systemImage: "text.alignleft")
                        Label("Hashtags", systemImage: "number")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 190, alignment: .leading)
                .roundedCard(padding: 22)

                if !store.allTags.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your tags").font(.headline)
                        FlowLayout(spacing: 8) {
                            ForEach(store.allTags) { tag in
                                Button {
                                    query = "#\(tag.name)"
                                } label: {
                                    HStack(spacing: 6) {
                                        Text("#\(tag.name)")
                                        Text("\(tag.count)").foregroundStyle(.tertiary)
                                    }
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 7)
                                    .background(AppTheme.card, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(16)
            .frame(maxWidth: .infinity)
        }
    }

    @MainActor
    private func performSearch(immediate: Bool = false) async {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            results = []
            searchError = nil
            return
        }
        if !immediate {
            try? await Task.sleep(for: .milliseconds(350))
        }
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            results = try await store.search(term)
            searchError = nil
        } catch is CancellationError {
            return
        } catch {
            searchError = error.localizedDescription
        }
    }
}
