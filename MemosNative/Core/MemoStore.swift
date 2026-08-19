import Foundation
import Observation

@MainActor
@Observable
final class MemoStore {
    private(set) var memos: [Memo] = []
    private(set) var archivedMemos: [Memo] = []
    private(set) var isLoading = false
    private(set) var isRefreshing = false
    private(set) var isLoadingArchive = false
    private(set) var hasLoadedTimeline = false
    private(set) var hasLoadedArchive = false
    var errorMessage: String?

    let api: MemosAPI
    let ownerName: String
    private let cacheKey: String
    private var nextPageToken: String?

    init(api: MemosAPI, ownerName: String) {
        self.api = api
        self.ownerName = ownerName
        self.cacheKey = "\(api.baseURL.absoluteString)-\(ownerName)".replacingOccurrences(
            of: "[^a-zA-Z0-9_-]",
            with: "-",
            options: .regularExpression
        )
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--demo-content") {
            memos = Self.demoMemos
            hasLoadedTimeline = true
            archivedMemos = [Self.demoArchivedMemo]
            hasLoadedArchive = true
        }
#endif
    }

    var allTags: [TagSummary] {
        let counts = memos.reduce(into: [String: Int]()) { partial, memo in
            memo.tags.forEach { partial[$0, default: 0] += 1 }
        }
        return counts
            .map { TagSummary(name: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                lhs.count == rhs.count
                    ? lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    : lhs.count > rhs.count
            }
    }

    func loadTimelineIfNeeded() async {
        guard !hasLoadedTimeline else { return }
        hasLoadedTimeline = true
        if let cached = await MemoCache.shared.load(key: cacheKey, state: .normal) {
            memos = cached
        }
        await refreshTimeline(showSpinner: memos.isEmpty)
    }

    func refreshTimeline(showSpinner: Bool = false) async {
        if showSpinner { isLoading = true } else { isRefreshing = true }
        defer {
            isLoading = false
            isRefreshing = false
        }
        do {
            let response = try await api.listMemos(
                state: .normal,
                pageSize: 50,
                filter: ownerFilter
            )
            memos = response.memos
            nextPageToken = response.nextPageToken
            errorMessage = nil
            await MemoCache.shared.save(memos, key: cacheKey, state: .normal)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreIfNeeded(current memo: Memo, matchingTag: String? = nil) async {
        let lastRelevantMemo = matchingTag.flatMap { tag in
            memos.last(where: { $0.tags.contains(tag) })
        } ?? memos.last
        guard memo.id == lastRelevantMemo?.id,
              nextPageToken?.isEmpty == false,
              !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            repeat {
                guard let pageToken = nextPageToken, !pageToken.isEmpty else { break }
                let response = try await api.listMemos(
                    state: .normal,
                    pageSize: 50,
                    pageToken: pageToken,
                    filter: ownerFilter
                )
                let existing = Set(memos.map(\.id))
                let newMemos = response.memos.filter { !existing.contains($0.id) }
                memos.append(contentsOf: newMemos)
                nextPageToken = response.nextPageToken

                if matchingTag == nil || newMemos.contains(where: { $0.tags.contains(matchingTag!) }) {
                    break
                }
            } while nextPageToken?.isEmpty == false
            await MemoCache.shared.save(memos, key: cacheKey, state: .normal)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadArchiveIfNeeded() async {
        guard !hasLoadedArchive else { return }
        hasLoadedArchive = true
        if let cached = await MemoCache.shared.load(key: cacheKey, state: .archived) {
            archivedMemos = cached
        }
        await refreshArchive()
    }

    func refreshArchive() async {
        isLoadingArchive = true
        defer { isLoadingArchive = false }
        do {
            let response = try await api.listMemos(
                state: .archived,
                pageSize: 100,
                filter: ownerFilter
            )
            archivedMemos = response.memos
            errorMessage = nil
            await MemoCache.shared.save(archivedMemos, key: cacheKey, state: .archived)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func create(
        content: String,
        visibility: MemoVisibility,
        attachments: [CreateAttachmentBody] = []
    ) async throws -> Memo {
        let memo = try await api.createMemo(content: content, visibility: visibility, attachments: attachments)
        memos.insert(memo, at: 0)
        await MemoCache.shared.save(memos, key: cacheKey, state: .normal)
        return memo
    }

    @discardableResult
    func update(_ memo: Memo) async throws -> Memo {
        let updated = try await api.updateMemo(memo)
        replace(updated)
        await saveCaches()
        return updated
    }

    func togglePin(_ memo: Memo) async {
        do {
            let updated = try await api.setPinned(!memo.pinned, for: memo)
            replace(updated)
            sortTimeline()
            await MemoCache.shared.save(memos, key: cacheKey, state: .normal)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func setArchived(_ archived: Bool, memo: Memo) async -> Bool {
        do {
            let updated = try await api.setArchived(archived, for: memo)
            if archived {
                memos.removeAll { $0.id == memo.id }
                archivedMemos.insert(updated, at: 0)
            } else {
                archivedMemos.removeAll { $0.id == memo.id }
                memos.insert(updated, at: 0)
                sortTimeline()
            }
            await saveCaches()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func delete(_ memo: Memo) async -> Bool {
        do {
            try await api.deleteMemo(memo)
            memos.removeAll { $0.id == memo.id }
            archivedMemos.removeAll { $0.id == memo.id }
            await saveCaches()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func search(_ query: String) async throws -> [Memo] {
        let escaped = query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let filter = "\(ownerFilter) && content.contains(\"\(escaped)\")"
        return try await api.listMemos(state: .normal, pageSize: 100, filter: filter).memos
    }

    func memos(from startDate: Date, to endDate: Date) async throws -> [Memo] {
        let start = Int64(startDate.timeIntervalSince1970.rounded(.down))
        let end = Int64(endDate.timeIntervalSince1970.rounded(.down))
        let filter = "\(ownerFilter) && created_ts >= timestamp(\(start)) && created_ts < timestamp(\(end))"

        var result: [Memo] = []
        var pageToken: String?
        repeat {
            let response = try await api.listMemos(
                state: .normal,
                pageSize: 1000,
                pageToken: pageToken,
                filter: filter
            )
            result.append(contentsOf: response.memos)
            pageToken = response.nextPageToken?.isEmpty == false ? response.nextPageToken : nil
        } while pageToken != nil

        return result.sorted { $0.createTime > $1.createTime }
    }

    private var ownerFilter: String {
        let escaped = ownerName.replacingOccurrences(of: "\"", with: "\\\"")
        return "creator == \"\(escaped)\""
    }

    private func replace(_ memo: Memo) {
        if let index = memos.firstIndex(where: { $0.id == memo.id }) {
            memos[index] = memo
        }
        if let index = archivedMemos.firstIndex(where: { $0.id == memo.id }) {
            archivedMemos[index] = memo
        }
    }

    private func sortTimeline() {
        memos.sort {
            if $0.pinned != $1.pinned { return $0.pinned && !$1.pinned }
            return $0.createTime > $1.createTime
        }
    }

    private func saveCaches() async {
        await MemoCache.shared.save(memos, key: cacheKey, state: .normal)
        await MemoCache.shared.save(archivedMemos, key: cacheKey, state: .archived)
    }

#if DEBUG
    private static let demoMemos: [Memo] = [
        Memo(
            name: "memos/welcome",
            createTime: .now.addingTimeInterval(-780),
            updateTime: .now.addingTimeInterval(-780),
            content: "# Plan for the week\n- [x] Review the launch notes\n- [ ] Send the new build to the team\n- [ ] Book a quiet afternoon for writing\n\nSmall steps, clearly captured. #planning",
            visibility: .privateMemo,
            tags: ["planning"],
            pinned: true,
            property: MemoProperty(hasLink: false, hasTaskList: true, hasCode: false, hasIncompleteTasks: true, title: "Plan for the week")
        ),
        Memo(
            name: "memos/idea",
            createTime: .now.addingTimeInterval(-7_400),
            updateTime: .now.addingTimeInterval(-7_400),
            content: "> The best tools feel quiet until the exact moment you need them.\n\nA thought for the product principles doc. #ideas #product",
            visibility: .protectedMemo,
            tags: ["ideas", "product"]
        ),
        Memo(
            name: "memos/reading",
            createTime: .now.addingTimeInterval(-92_000),
            updateTime: .now.addingTimeInterval(-88_000),
            content: "## Reading notes\nA useful distinction: **capture should be instant**, but organizing can happen later.\n\nhttps://usememos.com #reading",
            visibility: .privateMemo,
            tags: ["reading"]
        )
    ]

    private static let demoArchivedMemo = Memo(
        name: "memos/archive",
        state: .archived,
        createTime: .now.addingTimeInterval(-160_000),
        updateTime: .now.addingTimeInterval(-80_000),
        content: "An older idea kept here for later.",
        visibility: .privateMemo
    )
#endif
}

struct TagSummary: Identifiable, Hashable {
    let name: String
    let count: Int
    var id: String { name }
}

actor MemoCache {
    static let shared = MemoCache()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func load(key: String, state: MemoState) -> [Memo]? {
        guard let data = try? Data(contentsOf: fileURL(key: key, state: state)) else { return nil }
        return try? decoder.decode([Memo].self, from: data)
    }

    func save(_ memos: [Memo], key: String, state: MemoState) {
        guard let data = try? encoder.encode(memos) else { return }
        let url = fileURL(key: key, state: state)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private func fileURL(key: String, state: MemoState) -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base
            .appending(path: "MemosNative", directoryHint: .isDirectory)
            .appending(path: "\(key)-\(state.rawValue.lowercased()).json")
    }
}
