import QuickLook
import SwiftUI
import UIKit

enum AttachmentGalleryStyle {
    case compact
    case detail
}

struct AttachmentGallery: View {
    let attachments: [MemoAttachment]
    let api: MemosAPI
    let style: AttachmentGalleryStyle

    private var visibleAttachments: [MemoAttachment] {
        style == .compact ? Array(attachments.prefix(2)) : attachments
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Array(visibleAttachments.enumerated()), id: \.element.id) { index, attachment in
                AttachmentTile(
                    attachment: attachment,
                    api: api,
                    style: style,
                    overflowCount: style == .compact && index == 1 ? max(0, attachments.count - 2) : 0
                )
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var columns: [GridItem] {
        switch style {
        case .compact:
            Array(repeating: GridItem(.flexible(), spacing: 10), count: min(2, visibleAttachments.count))
        case .detail:
            [GridItem(.adaptive(minimum: 180, maximum: 320), spacing: 10)]
        }
    }
}

private struct AttachmentTile: View {
    let attachment: MemoAttachment
    let api: MemosAPI
    let style: AttachmentGalleryStyle
    let overflowCount: Int

    @State private var image: UIImage?
    @State private var isLoadingImage = false
    @State private var imageLoadFailed = false
    @State private var isPreparingPreview = false
    @State private var previewFile: PreviewFile?
    @State private var previewError: String?

    var body: some View {
        Group {
            if style == .detail {
                Button(action: preparePreview) { tile }
                    .buttonStyle(.plain)
            } else {
                tile
            }
        }
        .task(id: attachment.id) {
            await loadImageIfNeeded()
        }
        .sheet(item: $previewFile) { file in
            AttachmentQuickLook(url: file.url)
        }
        .alert("Attachment unavailable", isPresented: previewErrorBinding) {
            Button("OK", role: .cancel) { previewError = nil }
        } message: {
            Text(previewError ?? "Please try again.")
        }
    }

    private var tile: some View {
        ZStack(alignment: .bottomLeading) {
            preview

            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .center,
                endPoint: .bottom
            )

            HStack(alignment: .bottom, spacing: 7) {
                Image(systemName: attachment.systemImage)
                Text(attachment.filename)
                    .lineLimit(style == .compact ? 1 : 2)
                Spacer(minLength: 0)
                if isPreparingPreview {
                    ProgressView().tint(.white).controlSize(.small)
                } else if style == .detail {
                    Image(systemName: "arrow.up.forward.app")
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(10)

            if overflowCount > 0 {
                Color.black.opacity(0.42)
                Text("+\(overflowCount)")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: style == .compact ? 132 : 180)
        .background(Color(uiColor: .tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(attachment.filename)
        .accessibilityHint(style == .detail ? "Opens a preview" : "Attachment")
    }

    @ViewBuilder
    private var preview: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            ZStack {
                Color(uiColor: .tertiarySystemFill)
                if isLoadingImage {
                    ProgressView()
                } else {
                    Image(systemName: imageLoadFailed ? "exclamationmark.triangle" : attachment.systemImage)
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(imageLoadFailed ? Color.secondary : AppTheme.tint)
                }
            }
        }
    }

    @MainActor
    private func loadImageIfNeeded() async {
        guard attachment.isImage, image == nil, !isLoadingImage else { return }
        isLoadingImage = true
        defer { isLoadingImage = false }

        do {
            let data: Data
            do {
                data = try await api.attachmentData(for: attachment, thumbnail: true)
            } catch {
                guard !Task.isCancelled else { return }
                data = try await api.attachmentData(for: attachment)
            }
            guard !Task.isCancelled else { return }
            guard let loadedImage = UIImage(data: data) else {
                imageLoadFailed = true
                return
            }
            image = loadedImage
            imageLoadFailed = false
        } catch {
            guard !Task.isCancelled else { return }
            imageLoadFailed = true
        }
    }

    private func preparePreview() {
        guard !isPreparingPreview else { return }
        isPreparingPreview = true
        Task {
            defer { isPreparingPreview = false }
            do {
                let data = try await api.attachmentData(for: attachment)
                guard !Task.isCancelled else { return }
                let url = try await AttachmentFileCache.shared.store(
                    data,
                    attachment: attachment,
                    serverURL: api.baseURL
                )
                previewFile = PreviewFile(url: url)
            } catch {
                guard !Task.isCancelled else { return }
                previewError = error.localizedDescription
            }
        }
    }

    private var previewErrorBinding: Binding<Bool> {
        Binding(
            get: { previewError != nil },
            set: { if !$0 { previewError = nil } }
        )
    }
}

private struct PreviewFile: Identifiable {
    let url: URL
    var id: URL { url }
}

private actor AttachmentFileCache {
    static let shared = AttachmentFileCache()

    func store(_ data: Data, attachment: MemoAttachment, serverURL: URL) throws -> URL {
        let server = sanitized(serverURL.host ?? "server")
        let attachmentID = sanitized(attachment.resourceID)
        let filename = sanitized(URL(fileURLWithPath: attachment.filename).lastPathComponent)
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "MemosNative/Attachments/\(server)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "\(attachmentID)-\(filename)")
        try data.write(to: url, options: .atomic)
        return url
    }

    private func sanitized(_ value: String) -> String {
        let result = value.replacingOccurrences(
            of: "[^a-zA-Z0-9._-]",
            with: "-",
            options: .regularExpression
        )
        return result.isEmpty ? "attachment" : String(result.prefix(180))
    }
}

private struct AttachmentQuickLook: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: NSURL

        init(url: URL) {
            self.url = url as NSURL
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url
        }
    }
}
