import SwiftUI

struct MemoCard: View {
    let memo: Memo
    let store: MemoStore

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            NavigationLink {
                MemoDetailView(memo: memo, store: store)
            } label: {
                VStack(alignment: .leading, spacing: 13) {
                    metadata
                    MarkdownPreview(content: memo.content, compact: true)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    if !memo.attachments.isEmpty {
                        Label(
                            "\(memo.attachments.count) attachment\(memo.attachments.count == 1 ? "" : "s")",
                            systemImage: "paperclip"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    if !memo.tags.isEmpty {
                        tagRow
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            MemoMenu(memo: memo, store: store)
        }
        .roundedCard(padding: 16)
        .contextMenu {
            contextMenuItems
        }
        .accessibilityElement(children: .contain)
    }

    private var metadata: some View {
        HStack(spacing: 7) {
            if memo.pinned {
                Image(systemName: "pin.fill")
                    .foregroundStyle(AppTheme.tint)
                    .accessibilityLabel("Pinned")
            }
            Image(systemName: memo.visibility.systemImage)
                .foregroundStyle(.secondary)
                .accessibilityLabel(memo.visibility.title)
            Text(memo.createTime.memoRelativeText)
                .foregroundStyle(.secondary)
            if memo.updateTime.timeIntervalSince(memo.createTime) > 60 {
                Text("Edited")
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .font(.caption)
    }

    private var tagRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(memo.tags.prefix(5), id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.softTint, in: Capsule())
                }
            }
        }
        .scrollClipDisabled()
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button {
            Task { await store.togglePin(memo) }
        } label: {
            Label(memo.pinned ? "Unpin" : "Pin", systemImage: memo.pinned ? "pin.slash" : "pin")
        }
        Button {
            Task { await store.setArchived(true, memo: memo) }
        } label: {
            Label("Archive", systemImage: "archivebox")
        }
        ShareLink(item: memo.content) {
            Label("Share text", systemImage: "square.and.arrow.up")
        }
    }
}

struct MemoMenu: View {
    let memo: Memo
    let store: MemoStore
    var isArchived = false

    var body: some View {
        Menu {
            if !isArchived {
                Button {
                    Task { await store.togglePin(memo) }
                } label: {
                    Label(memo.pinned ? "Unpin" : "Pin", systemImage: memo.pinned ? "pin.slash" : "pin")
                }
            }
            Button {
                Task { await store.setArchived(!isArchived, memo: memo) }
            } label: {
                Label(isArchived ? "Restore" : "Archive", systemImage: isArchived ? "arrow.uturn.backward" : "archivebox")
            }
            ShareLink(item: memo.content) {
                Label("Share text", systemImage: "square.and.arrow.up")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More actions")
    }
}
