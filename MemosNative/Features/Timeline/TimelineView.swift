import SwiftUI

struct TimelineView: View {
    let store: MemoStore
    let user: MemosUser
    @Binding var showingComposer: Bool

    @State private var selectedTag: String?
    @State private var showingCalendar = false

    private var visibleMemos: [Memo] {
        guard let selectedTag else { return store.memos }
        return store.memos.filter { $0.tags.contains(selectedTag) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.warmBackground.ignoresSafeArea()
                content
            }
            .navigationTitle("Memos")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingCalendar = true
                    } label: {
                        Image(systemName: "calendar")
                    }
                    .accessibilityLabel("Open calendar")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingComposer = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("New memo")
                }
            }
            .sheet(isPresented: $showingCalendar) {
                CalendarView(store: store)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .refreshable { await store.refreshTimeline() }
            .task { await store.loadTimelineIfNeeded() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading && store.memos.isEmpty {
            TimelineSkeleton()
        } else if store.memos.isEmpty {
            ContentUnavailableView {
                Label("A quiet timeline", systemImage: "text.badge.plus")
            } description: {
                Text("Capture a thought, a link, or something worth remembering.")
            } actions: {
                Button("Write your first memo") { showingComposer = true }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 14) {
                    welcomeCard
                    if !store.allTags.isEmpty { tagFilter }
                    ForEach(visibleMemos) { memo in
                        MemoCard(memo: memo, store: store)
                            .onAppear {
                                Task { await store.loadMoreIfNeeded(current: memo, matchingTag: selectedTag) }
                            }
                    }
                    if store.isLoading {
                        ProgressView().padding(.vertical, 18)
                    }
                }
                .frame(maxWidth: 720)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var welcomeCard: some View {
        Button {
            showingComposer = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(AppTheme.softTint)
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.tint)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(greeting)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("What’s on your mind?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .roundedCard(padding: 14)
        }
        .buttonStyle(.plain)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let salutation = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
        return "\(salutation), \(user.preferredName)"
    }

    private var tagFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                tagButton(title: "All", tag: nil, count: store.memos.count)
                ForEach(store.allTags) { summary in
                    tagButton(title: "#\(summary.name)", tag: summary.name, count: summary.count)
                }
            }
            .padding(.vertical, 1)
        }
        .scrollClipDisabled()
    }

    private func tagButton(title: String, tag: String?, count: Int) -> some View {
        let isSelected = selectedTag == tag
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { selectedTag = tag }
        } label: {
            HStack(spacing: 5) {
                Text(title)
                Text("\(count)").foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.secondary.opacity(0.6))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(isSelected ? .white : .secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(isSelected ? AppTheme.tint : AppTheme.card, in: Capsule())
        }
        .buttonStyle(.plain)
    }

}

private struct TimelineSkeleton: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(0..<4, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 12) {
                        RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 96, height: 11)
                        RoundedRectangle(cornerRadius: 5).fill(.quaternary).frame(height: 15)
                        RoundedRectangle(cornerRadius: 5).fill(.quaternary).frame(width: index.isMultiple(of: 2) ? 220 : 280, height: 15)
                    }
                    .redacted(reason: .placeholder)
                    .roundedCard()
                }
            }
            .frame(maxWidth: 720)
            .padding(16)
            .frame(maxWidth: .infinity)
        }
    }
}
