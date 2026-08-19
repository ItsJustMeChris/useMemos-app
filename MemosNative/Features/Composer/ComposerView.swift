import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ComposerView: View {
    let store: MemoStore
    let editing: Memo?
    var onSaved: ((Memo) -> Void)?
    private let initialVisibility: MemoVisibility

    @State private var content: String
    @State private var visibility: MemoVisibility
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var pendingAttachments: [PendingAttachment] = []
    @State private var isProcessingPhotos = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingDiscardConfirmation = false
    @State private var showingPhotoPicker = false
    @State private var pendingPhotoPickerPresentation = false
    @State private var photoLoadGeneration = UUID()
    @State private var keyboardOverlap: CGFloat = 0
    @FocusState private var isEditorFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(store: MemoStore, editing: Memo? = nil, onSaved: ((Memo) -> Void)? = nil) {
        self.store = store
        self.editing = editing
        self.onSaved = onSaved
        let startingVisibility = editing?.visibility ?? MemoVisibility(
            rawValue: UserDefaults.standard.string(forKey: "defaultMemoVisibility") ?? "PRIVATE"
        ) ?? .privateMemo
        self.initialVisibility = startingVisibility
        _content = State(initialValue: editing?.content ?? "")
        _visibility = State(initialValue: startingVisibility)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack {
                    AppTheme.warmBackground.ignoresSafeArea()
                    editor
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .overlay(alignment: .bottom) {
                    VStack(spacing: 0) {
                        if !pendingAttachments.isEmpty || isProcessingPhotos { attachmentStrip }
                        floatingControls(showDismiss: keyboardOverlap > 0)
                    }
                    .padding(.bottom, controlsBottomPadding(safeAreaBottom: proxy.safeAreaInsets.bottom))
                    .transaction { transaction in
                        transaction.animation = nil
                    }
                }
            }
            .navigationTitle(editing == nil ? "New memo" : "Edit memo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasUnsavedChanges {
                            showingDiscardConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                    .confirmationDialog(
                        "Discard this memo?",
                        isPresented: $showingDiscardConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Discard", role: .destructive) { dismiss() }
                        Button("Keep Writing", role: .cancel) {}
                    } message: {
                        Text("Your unsaved changes will be lost.")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Post" : "Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(trimmedContent.isEmpty || isSaving || isProcessingPhotos)
                }
            }
            .interactiveDismissDisabled(true)
            .alert("Couldn’t save memo", isPresented: errorBinding) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
            .photosPicker(
                isPresented: $showingPhotoPicker,
                selection: $selectedPhotoItems,
                maxSelectionCount: 5,
                matching: .images
            )
            .onChange(of: selectedPhotoItems) { _, items in
                let generation = UUID()
                photoLoadGeneration = generation
                Task { await loadPhotos(items, generation: generation) }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                updateKeyboardOverlap(notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
                keyboardOverlap = 0
                if pendingPhotoPickerPresentation {
                    pendingPhotoPickerPresentation = false
                    Task { @MainActor in
                        await Task.yield()
                        showingPhotoPicker = true
                    }
                }
            }
            .task {
                do {
                    try await Task.sleep(for: .milliseconds(250))
                    try Task.checkCancellation()
                    isEditorFocused = true
                } catch is CancellationError {
                    return
                } catch {
                    return
                }
            }
        }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $content)
                .font(.body)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .focused($isEditorFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .accessibilityLabel("Memo content")

            if content.isEmpty {
                Text("Write something worth remembering…")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 17)
                    .padding(.vertical, 18)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func floatingControls(showDismiss: Bool) -> some View {
        if #available(iOS 26.0, *) {
            HStack(spacing: 10) {
                if editing == nil {
                    photoPickerControl
                        .buttonStyle(.glass)
                }
                keyboardVisibilityControl
                    .buttonStyle(.glass)
                Spacer()
                if isSaving { ProgressView().controlSize(.small) }
                if showDismiss {
                    Button {
                        isEditorFocused = false
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Dismiss keyboard")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 10)
        } else {
            HStack(spacing: 10) {
                if editing == nil {
                    photoPickerControl
                        .buttonStyle(.bordered)
                }
                keyboardVisibilityControl
                    .buttonStyle(.bordered)
                Spacer()
                if isSaving { ProgressView().controlSize(.small) }
                if showDismiss {
                    Button {
                        isEditorFocused = false
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Dismiss keyboard")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 10)
        }
    }

    private var photoPickerControl: some View {
        Button {
            presentPhotoPicker()
        } label: {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.body.weight(.medium))
                .frame(width: 32, height: 32)
        }
        .accessibilityLabel("Add photos")
    }

    private func presentPhotoPicker() {
        if keyboardOverlap <= 0 {
            showingPhotoPicker = true
        } else {
            pendingPhotoPickerPresentation = true
            isEditorFocused = false
        }
    }

    private func updateKeyboardOverlap(_ notification: Notification) {
        guard let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }
        let screenHeight = UIScreen.main.bounds.height
        let overlap = max(0, screenHeight - endFrame.minY)
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            keyboardOverlap = overlap
        }
    }

    private func controlsBottomPadding(safeAreaBottom: CGFloat) -> CGFloat {
        guard keyboardOverlap > 0 else { return 10 }
        return max(10, keyboardOverlap - safeAreaBottom + 10)
    }

    private var keyboardVisibilityControl: some View {
        Menu {
            ForEach(MemoVisibility.selectableCases) { option in
                Button {
                    visibility = option
                } label: {
                    Label(option.title, systemImage: option.systemImage)
                }
            }
        } label: {
            Image(systemName: visibility.systemImage)
                .frame(width: 30, height: 30)
        }
        .accessibilityLabel("Visibility: \(visibility.title)")
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(pendingAttachments) { attachment in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: attachment.thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 82, height: 82)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Button {
                            pendingAttachments.removeAll { $0.id == attachment.id }
                            selectedPhotoItems = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.65))
                                .font(.title3)
                        }
                        .offset(x: 6, y: -6)
                        .accessibilityLabel("Remove \(attachment.filename)")
                    }
                }
                if isProcessingPhotos {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(.quaternary)
                        ProgressView()
                    }
                    .frame(width: 82, height: 82)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private var trimmedContent: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasUnsavedChanges: Bool {
        content != (editing?.content ?? "")
            || visibility != initialVisibility
            || !pendingAttachments.isEmpty
    }

    private func save() {
        guard !trimmedContent.isEmpty, !isSaving else { return }
        isSaving = true
        errorMessage = nil

        Task {
            defer { isSaving = false }
            do {
                let saved: Memo
                if var editing {
                    editing.content = trimmedContent
                    editing.visibility = visibility
                    saved = try await store.update(editing)
                } else {
                    let attachments = pendingAttachments.map {
                        CreateAttachmentBody(
                            filename: $0.filename,
                            content: $0.data.base64EncodedString(),
                            type: $0.mimeType
                        )
                    }
                    saved = try await store.create(
                        content: trimmedContent,
                        visibility: visibility,
                        attachments: attachments
                    )
                }
                onSaved?(saved)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func loadPhotos(_ items: [PhotosPickerItem], generation: UUID) async {
        guard !items.isEmpty else { return }
        isProcessingPhotos = true
        defer {
            if generation == photoLoadGeneration { isProcessingPhotos = false }
        }
        pendingAttachments.removeAll()

        for (index, item) in items.enumerated() {
            do {
                guard let original = try await item.loadTransferable(type: Data.self),
                      generation == photoLoadGeneration else { return }
                let processed = await Task.detached(priority: .userInitiated) {
                    ProcessedPhoto.make(from: original)
                }.value
                guard generation == photoLoadGeneration,
                      let processed,
                      let thumbnail = UIImage(data: processed.thumbnailData) else { continue }
                pendingAttachments.append(
                    PendingAttachment(
                        filename: "photo-\(index + 1).jpg",
                        mimeType: UTType.jpeg.preferredMIMEType ?? "image/jpeg",
                        data: processed.uploadData,
                        thumbnail: thumbnail
                    )
                )
            } catch {
                errorMessage = "One of the selected photos couldn’t be prepared."
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

}

private struct PendingAttachment: Identifiable {
    let id = UUID()
    let filename: String
    let mimeType: String
    let data: Data
    let thumbnail: UIImage
}

private struct ProcessedPhoto: Sendable {
    let uploadData: Data
    let thumbnailData: Data

    static func make(from data: Data) -> ProcessedPhoto? {
        guard let image = UIImage(data: data),
              let uploadData = image.optimizedJPEGData(),
              let thumbnail = image.preparingThumbnail(of: CGSize(width: 240, height: 240)),
              let thumbnailData = thumbnail.jpegData(compressionQuality: 0.72) else { return nil }
        return ProcessedPhoto(uploadData: uploadData, thumbnailData: thumbnailData)
    }
}


private extension UIImage {
    func optimizedJPEGData(maxDimension: CGFloat = 2200) -> Data? {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return jpegData(compressionQuality: 0.84) }
        let scale = maxDimension / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: 0.84)
    }
}
