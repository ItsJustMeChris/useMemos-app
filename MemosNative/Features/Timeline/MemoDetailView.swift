import SwiftUI

struct MemoDetailView: View {
    @State private var memo: Memo
    let store: MemoStore

    @State private var showingEditor = false
    @State private var showingDeleteConfirmation = false
    @State private var isUpdatingTask = false
    @Environment(\.dismiss) private var dismiss

    init(memo: Memo, store: MemoStore) {
        _memo = State(initialValue: memo)
        self.store = store
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                metadata
                MarkdownPreview(content: memo.content, onToggleTask: toggleTask)
                if !memo.attachments.isEmpty {
                    Divider()
                    AttachmentSection(attachments: memo.attachments, serverURL: store.api.baseURL)
                }
                if !memo.tags.isEmpty { tags }
                Divider()
                footer
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.warmBackground)
        .navigationTitle(memo.displayTitle ?? "Memo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: memo.content) {
                    Image(systemName: "square.and.arrow.up")
                }
                Button("Edit", systemImage: "pencil") { showingEditor = true }
                Menu {
                    Button {
                        Task {
                            await store.togglePin(memo)
                            memo.pinned.toggle()
                        }
                    } label: {
                        Label(memo.pinned ? "Unpin" : "Pin", systemImage: memo.pinned ? "pin.slash" : "pin")
                    }
                    Button {
                        Task {
                            await store.setArchived(true, memo: memo)
                            dismiss()
                        }
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                    Divider()
                    Button(role: .destructive) { showingDeleteConfirmation = true } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            ComposerView(store: store, editing: memo) { updated in
                memo = updated
            }
        }
        .confirmationDialog(
            "Delete this memo?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
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

    private var metadata: some View {
        HStack(spacing: 8) {
            StatusPill(title: memo.visibility.title, systemImage: memo.visibility.systemImage)
            if memo.pinned {
                StatusPill(title: "Pinned", systemImage: "pin.fill", color: AppTheme.tint)
            }
            if isUpdatingTask { ProgressView().controlSize(.mini) }
            Spacer()
        }
    }

    private var tags: some View {
        FlowLayout(spacing: 7) {
            ForEach(memo.tags, id: \.self) { tag in
                Text("#\(tag)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.softTint, in: Capsule())
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Created \(memo.createTime.formatted(date: .long, time: .shortened))")
            if memo.updateTime.timeIntervalSince(memo.createTime) > 60 {
                Text("Last edited \(memo.updateTime.formatted(date: .abbreviated, time: .shortened))")
            }
        }
        .font(.footnote)
        .foregroundStyle(.tertiary)
    }

    private func toggleTask(lineIndex: Int, checked: Bool) {
        guard !isUpdatingTask else { return }
        var lines = memo.content.components(separatedBy: .newlines)
        guard lines.indices.contains(lineIndex) else { return }
        let original = lines[lineIndex]
        let leadingWhitespace = original.prefix(while: { $0.isWhitespace })
        let taskText = original.dropFirst(leadingWhitespace.count)
        if checked {
            lines[lineIndex] = String(leadingWhitespace) + taskText.replacingOccurrences(
                of: "- [ ]",
                with: "- [x]",
                options: [.caseInsensitive, .anchored]
            )
        } else {
            lines[lineIndex] = String(leadingWhitespace) + taskText.replacingOccurrences(
                of: "- [x]",
                with: "- [ ]",
                options: [.caseInsensitive, .anchored]
            )
        }
        let previous = memo
        memo.content = lines.joined(separator: "\n")
        isUpdatingTask = true
        Task {
            defer { isUpdatingTask = false }
            do {
                memo = try await store.update(memo)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } catch {
                memo = previous
                store.errorMessage = error.localizedDescription
            }
        }
    }
}

private struct AttachmentSection: View {
    let attachments: [MemoAttachment]
    let serverURL: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Attachments").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(attachments) { attachment in
                    attachmentView(attachment)
                }
            }
        }
    }

    @ViewBuilder
    private func attachmentView(_ attachment: MemoAttachment) -> some View {
        if attachment.isImage, let image = decodedImage(attachment) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else if attachment.isImage, let url = externalURL(attachment) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    ZStack { Color.secondary.opacity(0.1); ProgressView() }
                }
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            HStack(spacing: 10) {
                Image(systemName: "doc.fill").foregroundStyle(AppTheme.tint)
                Text(attachment.filename).font(.subheadline).lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func decodedImage(_ attachment: MemoAttachment) -> UIImage? {
        guard let content = attachment.content,
              let data = Data(base64Encoded: content) else { return nil }
        return UIImage(data: data)
    }

    private func externalURL(_ attachment: MemoAttachment) -> URL? {
        guard let link = attachment.externalLink, !link.isEmpty else { return nil }
        if let absolute = URL(string: link), absolute.scheme != nil { return absolute }
        return serverURL.appending(path: link.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var points: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return (CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + lineHeight), points)
    }
}
