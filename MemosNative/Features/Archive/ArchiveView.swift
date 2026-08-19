import SwiftUI

struct ArchiveView: View {
    let store: MemoStore

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.warmBackground.ignoresSafeArea()
                content
            }
            .navigationTitle("Archive")
            .task { await store.loadArchiveIfNeeded() }
            .refreshable { await store.refreshArchive() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoadingArchive && store.archivedMemos.isEmpty {
            ProgressView("Loading archive…")
        } else if store.archivedMemos.isEmpty {
            ContentUnavailableView {
                Label("Nothing archived", systemImage: "archivebox")
            } description: {
                Text("Memos you archive will stay safe here until you need them again.")
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(store.archivedMemos) { memo in
                        ArchivedMemoRow(memo: memo, store: store)
                    }
                }
                .frame(maxWidth: 720)
                .padding(16)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct ArchivedMemoRow: View {
    let memo: Memo
    let store: MemoStore

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            NavigationLink {
                ArchivedMemoDetailView(memo: memo, store: store)
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 7) {
                        Image(systemName: "archivebox.fill")
                        Text("Archived")
                        Text(memo.updateTime.memoRelativeText)
                        Spacer()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    MarkdownPreview(content: memo.content, compact: true)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                }
            }
            .buttonStyle(.plain)
            MemoMenu(memo: memo, store: store, isArchived: true)
        }
        .roundedCard()
    }
}

private struct ArchivedMemoDetailView: View {
    let memo: Memo
    let store: MemoStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                StatusPill(title: "Archived", systemImage: "archivebox.fill")
                MarkdownPreview(content: memo.content)
                Divider()
                Text("Archived \(memo.updateTime.formatted(date: .long, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.warmBackground)
        .navigationTitle(memo.displayTitle ?? "Archived memo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Restore", systemImage: "arrow.uturn.backward") {
                    Task {
                        await store.setArchived(false, memo: memo)
                        dismiss()
                    }
                }
                Menu {
                    ShareLink(item: memo.content) {
                        Label("Share text", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) { showingDeleteConfirmation = true } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Delete this memo?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Task {
                    await store.delete(memo)
                    dismiss()
                }
            }
        } message: {
            Text("This can’t be undone.")
        }
    }
}
